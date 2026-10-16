"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  requestHasAdminAccess,
} = require("../admin_authorization");

class FakeDocRef {
  constructor(store, path) {
    this.store = store;
    this.path = path;
  }

  async get() {
    const data = this.store.get(this.path);
    return {
      exists: data !== undefined,
      data: () => data,
    };
  }

  collection(name) {
    return new FakeCollectionRef(this.store, `${this.path}/${name}`);
  }
}

class FakeCollectionRef {
  constructor(store, path) {
    this.store = store;
    this.path = path;
  }

  doc(id) {
    return new FakeDocRef(this.store, `${this.path}/${id}`);
  }
}

class FakeDb {
  constructor(seed = {}) {
    this.store = new Map(Object.entries(seed));
  }

  collection(name) {
    return new FakeCollectionRef(this.store, name);
  }
}

function auth(uid, email) {
  return {
    uid,
    token: {
      email,
    },
  };
}

test("admin profile flag grants callable claim-review admin access", async () => {
  const db = new FakeDb({
    "users/moderator-1": { isAdmin: true },
  });

  assert.equal(
    await requestHasAdminAccess({
      db,
      auth: auth("moderator-1", "moderator@example.com"),
    }),
    true,
  );
});

test("private account admin flag grants callable admin access", async () => {
  const db = new FakeDb({
    "users/moderator-private/private/account": { isAdmin: true },
  });

  assert.equal(
    await requestHasAdminAccess({
      db,
      auth: auth("moderator-private", "moderator@example.com"),
    }),
    true,
  );
});

test("private account revocation overrides a stale legacy public admin flag", async () => {
  const db = new FakeDb({
    "users/revoked": { isAdmin: true },
    "users/revoked/private/account": { isAdmin: false },
  });

  assert.equal(
    await requestHasAdminAccess({
      db,
      auth: auth("revoked", "revoked@example.com"),
    }),
    false,
  );
});

test("approved admin email with enabled adminEmails doc remains allowed", async () => {
  const db = new FakeDb({
    "adminEmails/founder@locallinkapp.co.uk": { enabled: true },
  });

  assert.equal(
    await requestHasAdminAccess({
      db,
      auth: auth("founder-1", "FOUNDER@LocalLinkApp.co.uk"),
    }),
    true,
  );
});

test("approved admin email is denied when adminEmails doc is disabled", async () => {
  const db = new FakeDb({
    "adminEmails/founder@locallinkapp.co.uk": { enabled: false },
  });

  assert.equal(
    await requestHasAdminAccess({
      db,
      auth: auth("founder-1", "founder@locallinkapp.co.uk"),
    }),
    false,
  );
});

test("ordinary user without admin flag or approved email is denied", async () => {
  const db = new FakeDb({
    "adminEmails/member@example.com": { enabled: true },
    "users/member-1": { isAdmin: false },
  });

  assert.equal(
    await requestHasAdminAccess({
      db,
      auth: auth("member-1", "member@example.com"),
    }),
    false,
  );
});
