class InvitationService

  def self.create_invite_to_start_group(args)
    args[:to_be_admin] = true
    args[:intent] = 'start_group'
    args[:invitable] = args[:group]
    args.delete(:group)
    Invitation.create(args)
  end

  def self.create_invite_to_join_group(args)
    args[:to_be_admin] = false
    args[:intent] = 'join_group'
    args[:invitable] = args[:group]
    args.delete(:group)
    Invitation.create(args)
  end

  def self.invite_admin_to_group(group: , name:, email:)
    invitation = InvitationService.create_invite_to_start_group(group: group,
                                                                inviter: User.helper_bot,
                                                                recipient_email: email,
                                                                recipient_name: name)

    InvitePeopleMailer.delay(priority: 1).to_start_group(invitation: invitation,
                                                         sender_email: User.helper_bot_email,
                                                         locale: I18n.locale)
    invitation
  end

  def self.invite_to_group(recipient_emails: nil,
                           message: nil,
                           group: nil,
                           inviter: nil)
    (recipient_emails - group.members.pluck(:email)).map do |recipient_email|
      invitation = create_invite_to_join_group(recipient_email: recipient_email,
                                               group: group,
                                               message: message,
                                               inviter: inviter)

      InvitePeopleMailer.delay(priority: 1).to_join_group(invitation: invitation,
                                                          locale: I18n.locale)
      invitation
    end
  end

  def self.resend(invitation)
    return unless invitation.is_pending?
    InvitePeopleMailer.delay(priority: 1).to_join_group(invitation: invitation,
                                           locale: I18n.locale,
                                           subject_key: "email.resend_to_join_group.subject")
    invitation
  end

  def self.cancel(invitation:, actor:)
    actor.ability.authorize! :cancel, invitation
    invitation.cancel!(canceller: actor)
  end

  def self.shareable_invitation_for(group)
    if group.invitations.shareable.count == 0
      Invitation.create!(single_use: false,
                         intent: 'join_group',
                         invitable: group)
    end
    group.invitations.shareable.first
  end

  def self.redeem(invitation, user)
    raise Invitation::InvitationCancelled   if invitation.cancelled?
    raise Invitation::InvitationAlreadyUsed if invitation.accepted?

    invitation.accepted_at = DateTime.now if invitation.single_use?

    if invitation.to_be_admin?
      membership = invitation.group.add_admin!(user, invitation.inviter)
    else
      membership = invitation.group.add_member!(user, invitation.inviter)
    end
    invitation.save!
    Events::InvitationAccepted.publish!(membership)
  end

  def self.resend_ignored(send_count:, since:)
    Invitation.ignored(send_count, since).each { |invitation| resend invitation  }
  end
end
