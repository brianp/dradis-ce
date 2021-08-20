class Comment < ApplicationRecord
  include Notifiable

  MENTION_PATTERN = /[a-z0-9][a-z0-9\-@\.]*/.freeze

  # -- Relationships --------------------------------------------------------
  belongs_to :commentable, polymorphic: true
  belongs_to :user, optional: true

  # -- Callbacks ------------------------------------------------------------
  after_create :create_subscription

  # -- Validations ----------------------------------------------------------
  validates :content, presence: true, length: { maximum: DB_MAX_TEXT_LENGTH }
  validates :commentable, presence: true, associated: true

  # -- Scopes ---------------------------------------------------------------

  # -- Class Methods --------------------------------------------------------

  # -- Instance Methods -----------------------------------------------------
  # Because Issue descends from Note but doesn't use STI, Rails's default
  # polymorphic setter will set 'commentable_type' to 'Note' when you pass an
  # Issue to commentable. This means when you load the Activity later then
  # commentable will return the wrong class. Override the default behaviour here
  # for issues:
  #
  # FIXME - ISSUE/NOTE INHERITANCE
  def commentable=(new_commentable)
    super
    self.commentable_type = 'Issue' if new_commentable.is_a?(Issue)
    new_commentable
  end

  def create_subscription
    Subscription.subscribe(user: user, to: commentable) if user
  end

  def notify(action:, actor:, recipients:)
    case action.to_s
    when 'create'
      subscribe_mentioned()
      create_notifications(action: :mention, actor: actor,  recipients: mentions)

      # We're finding subscribers that have not been mention here
      # using ActiveRecord because create_notifications expect recipients
      # to be an ActiveRecord::Relation.
      subscribers = User.includes(:subscriptions).where(
        subscriptions: { subscribable_id: commentable.id }
      ).where.not(id: [user.id] + mentions.pluck(:id))
      create_notifications(action: :create, actor: actor, recipients: subscribers)
    end
  end

  def mentions
    @mentions = nil if content_changed?
    @mentions ||= begin
      emails = []
      HTML::Pipeline::MentionFilter.mentioned_logins_in(content, MENTION_PATTERN) do |_, login, _|
        emails << login
      end

      if commentable.respond_to?(:project)
        project = commentable.project
        project.testers_for_mentions.where(email: emails.uniq)
      else
        User.enabled.where(email: emails.uniq)
      end
    end
  end

  def to_xml(xml_builder, version: 3)
    xml_builder.content do
      xml_builder.cdata!(content)
    end
    xml_builder.author(user.email)
    xml_builder.created_at(created_at.to_i)
  end

  private

  def subscribe_mentioned
    mentions.each do |mention|
      Subscription.subscribe(user: mention, to: commentable)
    end
  end
end
