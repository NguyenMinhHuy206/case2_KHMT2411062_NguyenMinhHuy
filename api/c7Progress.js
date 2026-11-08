'use strict';

// Pure C7 role/status grouping, independent of Express and MongoDB.
// The caller supplies only tasks already authorized for the current user.
const ROLE_KEYS = ['created', 'assigned', 'shared'];
const STATUS_KEYS = ['pending', 'in_progress', 'completed'];

function idOf(value) {
  return value == null ? '' : String(value);
}

function normalizedStatus(status) {
  if (status === 'todo') return 'pending';
  return STATUS_KEYS.includes(status) ? status : 'pending';
}

function emptyGroup() {
  return {
    total: 0,
    counts: { pending: 0, in_progress: 0, completed: 0 },
    completionPercent: 0,
    tasks: []
  };
}

function addTask(group, task) {
  group.tasks.push(task);
  group.total += 1;
  group.counts[normalizedStatus(task.status)] += 1;
}

function finishGroup(group) {
  group.completionPercent = group.total === 0
    ? 0
    : Math.round(100 * group.counts.completed / group.total);
}

function buildC7Progress({ tasks, shares, userId, serializeTask }) {
  const uid = idOf(userId);
  const sharePermissionById = new Map();
  for (const share of shares) {
    if (share && share.taskId != null) {
      sharePermissionById.set(idOf(share.taskId), share.permission === 'editor' ? 'editor' : 'viewer');
    }
  }

  const groups = {
    all: emptyGroup(),
    created: emptyGroup(),
    assigned: emptyGroup(),
    shared: emptyGroup()
  };

  // Defensively de-duplicate, even if the query or incoming data includes duplicates.
  const seenIds = new Set();
  for (const task of tasks) {
    const taskId = idOf(task._id);
    if (!taskId || seenIds.has(taskId)) continue;
    seenIds.add(taskId);

    const roles = {
      created: idOf(task.createdBy) === uid,
      assigned: (task.assigneeIds || []).some(id => idOf(id) === uid),
      primaryAssignee: idOf(task.primaryAssigneeId) === uid,
      shared: sharePermissionById.has(taskId)
    };
    // Defense in depth: never return a task unless it has an allowed role.
    if (!ROLE_KEYS.some(role => roles[role])) continue;

    const item = {
      ...serializeTask(task),
      roles,
      sharePermission: roles.shared ? sharePermissionById.get(taskId) : null
    };
    addTask(groups.all, item);
    for (const role of ROLE_KEYS) {
      if (roles[role]) addTask(groups[role], item);
    }
  }

  for (const group of Object.values(groups)) finishGroup(group);

  return {
    total: groups.all.total,
    groups,
    // Scope totals can overlap; only groups.all.total is the unique task count.
    overlappingRolesAllowed: true
  };
}

module.exports = { buildC7Progress };
