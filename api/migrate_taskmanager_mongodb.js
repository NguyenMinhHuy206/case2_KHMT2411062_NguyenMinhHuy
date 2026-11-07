'use strict';

// TaskManager JSON -> MongoDB Atlas migration.
// Preview: node migrate_taskmanager_mongodb.js --dry-run
// Import:  node migrate_taskmanager_mongodb.js --apply
// Keep users.json and tasks.json; never commit api/.env or JSON backups.

const fs = require('fs');
const path = require('path');
const { connectDatabase, mongoose } = require('./config/database');
const { ObjectId } = mongoose.Types;

const COLLECTIONS = [
  'users', 'tasks', 'task_shares',
  'notifications', 'email_logs', 'task_activities'
];
const USER_KEYS = new Set(['id','name','email','passwordHash','tokenVersion','avatarUrl','createdAt','updatedAt']);
const TASK_KEYS = new Set([
  'id','title','description','status','priority','startDate','dueDate',
  'createdBy','createdAt','updatedAt','assigneeIds','primaryAssigneeId','shares'
]);

function assert(condition, message) {
  if (!condition) throw new Error(message);
}
function readArray(filename) {
  const pathname = path.join(__dirname, filename);
  const value = JSON.parse(fs.readFileSync(pathname, 'utf8').replace(/^\uFEFF/, ''));
  assert(Array.isArray(value), `${filename} khong phai mang JSON`);
  return value;
}
function unknownFields(record, allowed, entity) {
  const fields = Object.keys(record).filter(key => !allowed.has(key));
  assert(fields.length === 0, `${entity} co truong chua xu ly: ${fields.join(', ')}`);
}
function parsedTimestamp(input, fallback, field) {
  if (input == null) return fallback;
  const date = new Date(input);
  assert(Number.isFinite(date.getTime()), `Ngay khong hop le: ${field}`);
  return date;
}
function parsedDateOnly(input, field) {
  if (input == null || input === '') return null;
  assert(typeof input === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(input),
    `Dinh dang ngay khong hop le: ${field}`);
  const date = new Date(input + 'T00:00:00.000Z');
  assert(Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === input,
    `Ngay khong hop le: ${field}`);
  return date;
}
function asId(input, field) {
  assert(typeof input === 'string' && input.trim(), `Thieu ID: ${field}`);
  return input;
}

function prepare() {
  const sourceUsers = readArray('users.json');
  const sourceTasks = readArray('tasks.json');
  assert(sourceUsers.length === 9, `So users khac 9: ${sourceUsers.length}`);
  assert(sourceTasks.length === 4, `So tasks khac 4: ${sourceTasks.length}`);

  const now = new Date();
  const userMap = new Map();
  const seenEmails = new Set();
  const users = sourceUsers.map((u) => {
    unknownFields(u, USER_KEYS, 'User');
    const legacyId = asId(u.id, 'user.id');
    assert(!userMap.has(legacyId), 'Trung user.id');
    const email = String(u.email || '').trim().toLowerCase();
    assert(/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email), 'Email khong hop le');
    assert(!seenEmails.has(email), 'Email bi trung');
    seenEmails.add(email);
    assert(typeof u.passwordHash === 'string' && /^\$2[aby]\$\d{2}\$/.test(u.passwordHash),
      'passwordHash khong phai bcrypt');
    const fullName = String(u.name || '').trim();
    assert(fullName.length >= 2, 'User thieu ho ten');
    const _id = new ObjectId();
    userMap.set(legacyId, _id);
    return {
      _id, legacyId, fullName, email, passwordHash: u.passwordHash,
      avatarUrl: u.avatarUrl || null,
      tokenVersion: Number.isInteger(u.tokenVersion) ? u.tokenVersion : 0,
      createdAt: parsedTimestamp(u.createdAt, now, 'user.createdAt'),
      updatedAt: parsedTimestamp(u.updatedAt, now, 'user.updatedAt')
    };
  });

  const taskIds = new Set();
  let assignedCount = 0;
  const tasks = sourceTasks.map((t) => {
    unknownFields(t, TASK_KEYS, 'Task');
    const legacyId = asId(t.id, 'task.id');
    assert(!taskIds.has(legacyId), 'Trung task.id');
    taskIds.add(legacyId);
    const createdBy = userMap.get(asId(t.createdBy, 'task.createdBy'));
    assert(createdBy, 'Task tham chieu nguoi tao khong ton tai');
    const sourceAssignees = t.assigneeIds == null ? [] : t.assigneeIds;
    assert(Array.isArray(sourceAssignees), 'assigneeIds khong phai mang');
    assert(new Set(sourceAssignees).size === sourceAssignees.length, 'assigneeIds bi trung');
    const assigneeIds = sourceAssignees.map(id => {
      const mongoId = userMap.get(asId(id, 'task.assigneeIds'));
      assert(mongoId, 'Task tham chieu nguoi duoc giao khong ton tai');
      return mongoId;
    });
    if (assigneeIds.length) assignedCount++;
    assert(t.shares == null || (Array.isArray(t.shares) && t.shares.length === 0),
      'Da co chia se: can chuyen task_shares rieng truoc khi import');
    const primary = t.primaryAssigneeId == null ? null : userMap.get(t.primaryAssigneeId);
    assert(t.primaryAssigneeId == null || primary, 'primaryAssigneeId khong ton tai');
    assert(primary == null || assigneeIds.some(id => id.equals(primary)),
      'primaryAssigneeId khong nam trong assigneeIds');
    assert(typeof t.title === 'string' && t.title.trim().length > 0 && t.title.length <= 200,
      'Tieu de task khong hop le');
    assert(typeof t.description === 'string' && t.description.length <= 5000,
      'Mo ta task khong hop le');
    assert(['pending','todo','in_progress','completed'].includes(t.status), 'Status khong hop le');
    assert(['low','medium','high'].includes(t.priority), 'Priority khong hop le');
    const startDate = parsedDateOnly(t.startDate, 'startDate');
    const dueDate = parsedDateOnly(t.dueDate, 'dueDate');
    assert(!startDate || !dueDate || dueDate >= startDate, 'Ngay bat dau sau ngay het han');
    const createdAt = parsedTimestamp(t.createdAt, now, 'task.createdAt');
    const updatedAt = parsedTimestamp(t.updatedAt, now, 'task.updatedAt');
    return {
      _id: new ObjectId(), legacyId, title: t.title.trim(), description: t.description,
      createdBy, assigneeIds, primaryAssigneeId: primary,
      status: t.status, priority: t.priority,
      startDate, dueDate, createdAt, updatedAt
    };
  });

  return { users, tasks, assignedCount };
}

async function main() {
  const mode = process.argv[2];
  assert(['--dry-run', '--apply'].includes(mode),
    'Dung: node migrate_taskmanager_mongodb.js --dry-run (hoac --apply)');
  const data = prepare();
  console.log('LOCAL_USERS:', data.users.length);
  console.log('LOCAL_TASKS:', data.tasks.length);
  console.log('TASKS_WITH_ASSIGNEES:', data.assignedCount);
  console.log('LEGACY_LINKS_VALID: YES');

  await connectDatabase();
  const db = mongoose.connection.db;
  const counts = {};
  for (const name of COLLECTIONS) {
    counts[name] = await db.collection(name).countDocuments({});
  }
  console.log('ATLAS_USERS:', counts.users);
  console.log('ATLAS_TASKS:', counts.tasks);
  assert(Object.values(counts).every(count => count === 0),
    'STOP: Atlas da co du lieu trong mot trong 6 collections; khong ghi de');

  if (mode === '--dry-run') {
    console.log('MIGRATION_DRY_RUN_OK');
    console.log('Chua ghi bat ky ban ghi nao len MongoDB.');
    return;
  }

  // A MongoDB transaction prevents a partly imported database if insertion fails.
  const session = await mongoose.startSession();
  try {
    await session.withTransaction(async () => {
      const users = db.collection('users');
      const tasks = db.collection('tasks');
      // Recheck inside the transaction; never overwrite existing data.
      assert((await users.countDocuments({}, {session})) === 0, 'users khong rong');
      assert((await tasks.countDocuments({}, {session})) === 0, 'tasks khong rong');
      await users.insertMany(data.users, {session, ordered: true});
      await tasks.insertMany(data.tasks, {session, ordered: true});
      assert((await users.countDocuments({}, {session})) === data.users.length,
        'So users sau khi insert khong khop');
      assert((await tasks.countDocuments({}, {session})) === data.tasks.length,
        'So tasks sau khi insert khong khop');
    });
  } finally {
    await session.endSession();
  }
  console.log('MIGRATION_APPLY_OK');
  console.log('IMPORTED_USERS:', data.users.length);
  console.log('IMPORTED_TASKS:', data.tasks.length);
  console.log('JSON_SOURCE_UNCHANGED: YES');
  console.log('Luu y: Backend chua duoc chuyen sang doc MongoDB.');
}

main()
  .catch(error => {
    console.error('MIGRATION_FAILED:', error.message);
    process.exitCode = 1;
  })
  .finally(async () => { await mongoose.disconnect(); });
