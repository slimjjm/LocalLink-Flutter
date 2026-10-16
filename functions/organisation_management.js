"use strict";

const crypto = require("crypto");

const ORGANISATION_ROLES = {
  OWNER: "owner",
  ADMIN: "organisation_admin",
  SECRETARY: "secretary",
  GROUP_LEADER: "group_leader",
  MEMBER: "member",
};

const MANAGER_ROLES = new Set([
  ORGANISATION_ROLES.OWNER,
  ORGANISATION_ROLES.ADMIN,
  ORGANISATION_ROLES.SECRETARY,
]);

function safeTrim(value) {
  return String(value ?? "").trim();
}

function normaliseEmail(value) {
  return safeTrim(value).toLowerCase();
}

function normaliseRole(value) {
  const role = safeTrim(value);
  return Object.values(ORGANISATION_ROLES).includes(role)
    ? role
    : ORGANISATION_ROLES.MEMBER;
}

function roleLabel(role) {
  switch (normaliseRole(role)) {
    case ORGANISATION_ROLES.OWNER:
      return "Owner";
    case ORGANISATION_ROLES.ADMIN:
      return "Organisation admin";
    case ORGANISATION_ROLES.SECRETARY:
      return "Secretary";
    case ORGANISATION_ROLES.GROUP_LEADER:
      return "Group leader";
    default:
      return "Member";
  }
}

function isValidEmail(value) {
  return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(normaliseEmail(value));
}

function canManageOrganisationRole({ uid, organisation, member }) {
  if (!uid || !organisation) return false;
  if (safeTrim(organisation.ownerId) === uid) return true;
  if (Array.isArray(organisation.adminUserIds) && organisation.adminUserIds.includes(uid)) {
    return true;
  }
  return member?.status === "active" && MANAGER_ROLES.has(member.role);
}

function canAssignRole({ actorRole, targetRole }) {
  const actor = normaliseRole(actorRole);
  const target = normaliseRole(targetRole);
  if (actor === ORGANISATION_ROLES.OWNER) return target !== ORGANISATION_ROLES.OWNER;
  if (actor === ORGANISATION_ROLES.ADMIN) return target !== ORGANISATION_ROLES.OWNER;
  if (actor === ORGANISATION_ROLES.SECRETARY) {
    return [
      ORGANISATION_ROLES.SECRETARY,
      ORGANISATION_ROLES.GROUP_LEADER,
      ORGANISATION_ROLES.MEMBER,
    ].includes(target);
  }
  return false;
}

function invitationToken() {
  return crypto.randomBytes(24).toString("hex");
}

function tokenHash(token) {
  return crypto.createHash("sha256").update(safeTrim(token)).digest("hex");
}

function invitationLink(token) {
  const encoded = encodeURIComponent(token);
  return `https://locallinkapp.co.uk/invitations/organisation/${encoded}`;
}

function buildOrganisationInvitationEmail({
  email,
  organisationName,
  inviterName,
  role,
  link,
}) {
  const label = roleLabel(role).toLowerCase();
  const intro = `${inviterName || "Someone"} invited you to join ${organisationName || "their organisation"} on LocalLink as ${label}.`;
  const text = `${intro}\n\nAccept invitation:\n${link}\n\nIf you were not expecting this, you can ignore this email.`;
  const html = `<!doctype html>
<html>
  <body style="margin:0;background:#f7f3ee;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#26221f;">
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f7f3ee;padding:24px 12px;">
      <tr><td align="center">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:560px;background:#fffaf4;border:1px solid #eadfd3;border-radius:14px;overflow:hidden;">
          <tr><td style="padding:24px;">
            <div style="font-size:14px;font-weight:700;color:#7b5f42;">LocalLink</div>
            <h1 style="margin:14px 0 8px;font-size:26px;line-height:1.2;color:#26221f;">You're invited</h1>
            <p style="margin:0 0 20px;color:#5d554e;font-size:15px;line-height:1.5;">${escapeHtml(intro)}</p>
            <a href="${escapeHtml(link)}" style="display:inline-block;background:#2f6fed;color:#ffffff;text-decoration:none;border-radius:8px;padding:12px 16px;font-weight:700;">Accept invitation</a>
            <p style="margin:20px 0 0;color:#8a817a;font-size:13px;line-height:1.5;">If you were not expecting this, you can ignore this email.</p>
          </td></tr>
        </table>
      </td></tr>
    </table>
  </body>
</html>`;
  return {
    to: normaliseEmail(email),
    subject: `Invitation to ${organisationName || "LocalLink"}`,
    html,
    text,
  };
}

function escapeHtml(value) {
  return safeTrim(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

module.exports = {
  ORGANISATION_ROLES,
  MANAGER_ROLES,
  buildOrganisationInvitationEmail,
  canAssignRole,
  canManageOrganisationRole,
  invitationLink,
  invitationToken,
  isValidEmail,
  normaliseEmail,
  normaliseRole,
  roleLabel,
  tokenHash,
};
