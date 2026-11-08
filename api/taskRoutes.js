'use strict';

const express = require('express');
const mongoose = require('mongoose');
const User = require('./models/User');
const Task = require('./models/Task');
const TaskShare = require('./models/TaskShare');

module.exports = function createTaskRouter(auth) {
  const router = express.Router();

  function publicUserId(user) {
    return user.legacyId || String(user._id);
  }

  function publicTaskId(task) {
    return task.legacyId || String(task._id);
  }

  function objectIdString(value) {
    return value == null ? null : String(value);
  }

  function idFilter(id) {
    const conditions = [{ legacyId: String(id) }];
    if (/^[\da-f]{24}$/i.test(String(id))) {
      conditions.push({ _id: new mongoose.Types.ObjectId(String(id)) });
    }
    return { $or: conditions };
  }

  function dateOnly(date) {
    return date == null ? null : new Date(date).toISOString().slice(0, 10);
  }

  function validDate(date) {
    if (date === null) return true;
    if (typeof date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(date)) return false;
    const d = new Date(`${date}T00:00:00.000Z`);
    return Number.isFinite(d.getTime()) && d.toISOString().slice(0, 10) === date;
  }

  function validateFields(body) {
    const title = typeof body.title === 'string' ? body.title.trim() : '';
    const description = body.description == null ? '' : body.description;
    const status = body.status ?? 'pending';
    const priority = body.priority ?? 'medium';
    const startDate = body.startDate === '' ? null : (body.startDate ?? null);
    const dueDate = body.dueDate === '' ? null : (body.dueDate ?? null);
    if (!title || title.length > 200) return { error: 'Tiêu đề phải có từ 1 đến 200 ký tự.' };
    if (typeof description !== 'string' || description.length > 5000) return { error: 'Mô tả không hợp lệ hoặc quá dài.' };
    if (!['pending', 'in_progress', 'completed'].includes(status)) return { error: 'Trạng thái không hợp lệ.' };
    if (!['low', 'medium', 'high'].includes(priority)) return { error: 'Độ ưu tiên không hợp lệ.' };
    if (!validDate(startDate) || !validDate(dueDate)) return { error: 'Ngày phải đúng định dạng YYYY-MM-DD và là ngày hợp lệ.' };
    if (startDate && dueDate && dueDate < startDate) return { error: 'Hạn hoàn thành phải từ ngày bắt đầu trở đi.' };
    return { fields: { title, description, status, priority, startDate, dueDate } };
  }

  function dateAsMongo(value) {
    return value == null ? null : new Date(`${value}T00:00:00.000Z`);
  }

  function error500(res, error) {
    console.error(error);
    return res.status(500).json({ message: 'Lỗi máy chủ.' });
  }

  function canReadTask(task, userId) {
    return objectIdString(task.createdBy) === objectIdString(userId) ||
      (task.assigneeIds || []).some(id => objectIdString(id) === objectIdString(userId));
  }

  function canManageTask(task, userId) {
    return objectIdString(task.createdBy) === objectIdString(userId);
  }

  // C3: Nguoi duoc chia se co quyen xem cong viec, ke ca khi khong duoc giao C1.
  async function canReadTaskIncludingShare(task, userId) {
    if (canReadTask(task, userId)) return true;
    return Boolean(await TaskShare.exists({ taskId: task._id, userId }));
  }

  async function taskForRequest(id, userId) {
    const task = await Task.findOne(idFilter(id)).lean();
    if (!task || !(await canReadTaskIncludingShare(task, userId))) return null;
    return task;
  }

  async function userDictionary(taskList) {
    const ids = new Set();
    for (const task of taskList) {
      if (task.createdBy) ids.add(String(task.createdBy));
      for (const id of task.assigneeIds || []) ids.add(String(id));
      if (task.primaryAssigneeId) ids.add(String(task.primaryAssigneeId));
    }
    if (!ids.size) return new Map();
    const users = await User.find({ _id: { $in: [...ids] } }).lean();
    return new Map(users.map(user => [String(user._id), publicUserId(user)]));
  }

  function toClientTask(task, users) {
    const mapId = value => value == null ? null :
      (users.get(String(value)) || String(value));
    return {
      id: publicTaskId(task),
      title: task.title,
      description: task.description ?? '',
      status: task.status === 'todo' ? 'pending' : task.status,
      priority: task.priority,
      startDate: dateOnly(task.startDate),
      dueDate: dateOnly(task.dueDate),
      createdBy: mapId(task.createdBy),
      assigneeIds: (task.assigneeIds || []).map(mapId),
      primaryAssigneeId: mapId(task.primaryAssigneeId),
      shares: [], // Danh sach C3 truy van qua GET /:id/shares; truong cu giu de tuong thich.
      createdAt: new Date(task.createdAt).toISOString(),
      updatedAt: new Date(task.updatedAt).toISOString()
    };
  }

  async function clientTask(task) {
    const plain = typeof task.toObject === 'function' ? task.toObject() : task;
    const users = await userDictionary([plain]);
    return toClientTask(plain, users);
  }

  // B1: Danh sach cong viec do nguoi dung tao hoac duoc giao.
  router.get('/', auth, async (req, res) => {
    try {
      // C3: Bo sung cong viec duoc chia se vao danh sach, khong trung cong viec C1.
      const sharedTaskIds = await TaskShare.find({ userId: req.user._id }).distinct('taskId');
      const tasks = await Task.find({
        $or: [
          { createdBy: req.user._id },
          { assigneeIds: req.user._id },
          { _id: { $in: sharedTaskIds } }
        ]
      }).sort({ createdAt: -1 }).lean();
      const users = await userDictionary(tasks);
      return res.json({ total: tasks.length, tasks: tasks.map(t => toClientTask(t, users)) });
    } catch (error) { return error500(res, error); }
  });

  // B2: Tao cong viec.
  router.post('/', auth, async (req, res) => {
    try {
      const check = validateFields(req.body || {});
      if (check.error) return res.status(400).json({ message: check.error });
      const fields = check.fields;
      const task = await Task.create({
        title: fields.title, description: fields.description,
        status: fields.status, priority: fields.priority,
        startDate: dateAsMongo(fields.startDate), dueDate: dateAsMongo(fields.dueDate),
        createdBy: req.user._id, assigneeIds: [], primaryAssigneeId: null
      });
      return res.status(201).json({ message: 'Tạo công việc thành công.', task: await clientTask(task) });
    } catch (error) { return error500(res, error); }
  });

  // B2: Chi tiet cong viec.
  router.get('/:id', auth, async (req, res) => {
    try {
      const task = await taskForRequest(req.params.id, req.user._id);
      if (!task) return res.status(404).json({ message: 'Không tìm thấy công việc hoặc bạn không có quyền truy cập.' });
      return res.json({
        task: await clientTask(task),
        canManage: canManageTask(task, req.user._id),
        canChangeStatus: canReadTask(task, req.user._id)
      });
    } catch (error) { return error500(res, error); }
  });

  // B2: Sua noi dung; chi nguoi tao duoc phep.
  router.put('/:id', auth, async (req, res) => {
    try {
      const task = await Task.findOne({
        ...idFilter(req.params.id), createdBy: req.user._id
      });
      if (!task) return res.status(404).json({ message: 'Không tìm thấy công việc hoặc bạn không có quyền chỉnh sửa.' });
      const check = validateFields({
        title: task.title, description: task.description, status: task.status === 'todo' ? 'pending' : task.status,
        priority: task.priority, startDate: dateOnly(task.startDate), dueDate: dateOnly(task.dueDate),
        ...(req.body || {})
      });
      if (check.error) return res.status(400).json({ message: check.error });
      Object.assign(task, {
        title: check.fields.title, description: check.fields.description,
        status: check.fields.status, priority: check.fields.priority,
        startDate: dateAsMongo(check.fields.startDate), dueDate: dateAsMongo(check.fields.dueDate)
      });
      await task.save();
      return res.json({ message: 'Cập nhật công việc thành công.', task: await clientTask(task) });
    } catch (error) { return error500(res, error); }
  });

  // B3: Nguoi tao hoac nguoi duoc giao duoc cap nhat trang thai.
  router.patch('/:id/status', auth, async (req, res) => {
    try {
      const status = req.body?.status;
      if (!['pending', 'in_progress', 'completed'].includes(status)) {
        return res.status(400).json({ message: 'Trạng thái không hợp lệ.' });
      }
      const task = await Task.findOneAndUpdate({
        $and: [
          idFilter(req.params.id),
          { $or: [{ createdBy: req.user._id }, { assigneeIds: req.user._id }] }
        ]
      }, { $set: { status } }, { new: true, runValidators: true });
      if (!task) return res.status(404).json({ message: 'Không tìm thấy công việc hoặc bạn không có quyền cập nhật.' });
      return res.json({ message: 'Cập nhật trạng thái thành công.', task: await clientTask(task) });
    } catch (error) { return error500(res, error); }
  });

  // B4: Chi nguoi tao duoc cap nhat uu tien.
  router.patch('/:id/priority', auth, async (req, res) => {
    try {
      const priority = req.body?.priority;
      if (!['low', 'medium', 'high'].includes(priority)) {
        return res.status(400).json({ message: 'Mức độ ưu tiên không hợp lệ.' });
      }
      const task = await Task.findOneAndUpdate({
        ...idFilter(req.params.id), createdBy: req.user._id
      }, { $set: { priority } }, { new: true, runValidators: true });
      if (!task) return res.status(404).json({ message: 'Không tìm thấy công việc hoặc bạn không có quyền cập nhật.' });
      return res.json({ message: 'Cập nhật mức độ ưu tiên thành công.', task: await clientTask(task) });
    } catch (error) { return error500(res, error); }
  });

  // B5: Chi nguoi tao duoc sua ngay bat dau / han hoan thanh.
  router.patch('/:id/dates', auth, async (req, res) => {
    try {
      const body = req.body || {};
      if (!Object.prototype.hasOwnProperty.call(body, 'startDate') ||
          !Object.prototype.hasOwnProperty.call(body, 'dueDate')) {
        return res.status(400).json({ message: 'Cần gửi startDate và dueDate (YYYY-MM-DD hoặc null).' });
      }
      const task = await Task.findOne({
        ...idFilter(req.params.id), createdBy: req.user._id
      });
      if (!task) return res.status(404).json({ message: 'Không tìm thấy công việc hoặc bạn không có quyền cập nhật.' });
      const check = validateFields({
        title: task.title, description: task.description,
        status: task.status === 'todo' ? 'pending' : task.status, priority: task.priority,
        startDate: body.startDate, dueDate: body.dueDate
      });
      if (check.error) return res.status(400).json({ message: check.error });
      task.startDate = dateAsMongo(check.fields.startDate);
      task.dueDate = dateAsMongo(check.fields.dueDate);
      await task.save();
      return res.json({ message: 'Cập nhật ngày bắt đầu và hạn hoàn thành thành công.', task: await clientTask(task) });
    } catch (error) { return error500(res, error); }
  });

  // B2: Xoa cong viec; chi chu so huu.
  router.delete('/:id', auth, async (req, res) => {
    try {
      const task = await Task.findOneAndDelete({
        ...idFilter(req.params.id), createdBy: req.user._id
      });
      if (!task) return res.status(404).json({ message: 'Không tìm thấy công việc hoặc bạn không có quyền xóa.' });
      return res.json({ message: 'Xóa công việc thành công.' });
    } catch (error) { return error500(res, error); }
  });

  // C1: Tim tai khoan theo email, khong tra ve passwordHash.
  router.get('/members/search', auth, async (req, res) => {
    try {
      const email = String(req.query.email || '').trim().toLowerCase();
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        return res.status(400).json({ message: 'Nhập email đầy đủ và hợp lệ.' });
      }
      const user = await User.findOne({ email }).lean();
      if (!user || String(user._id) === String(req.user._id)) {
        return res.status(404).json({ message: 'Không tìm thấy tài khoản với email này.' });
      }
      return res.json({ user: { id: publicUserId(user), name: user.fullName, email: user.email } });
    } catch (error) { return error500(res, error); }
  });

  router.get('/:id/assignees', auth, async (req, res) => {
    try {
      const task = await taskForRequest(req.params.id, req.user._id);
      if (!task) return res.status(404).json({ message: 'Không tìm thấy công việc hoặc bạn không có quyền truy cập.' });
      const users = await User.find({ _id: { $in: task.assigneeIds || [] } }).lean();
      const dict = new Map(users.map(u => [String(u._id), u]));
      const assignees = (task.assigneeIds || []).map(id => dict.get(String(id))).filter(Boolean)
        .map(u => ({ id: publicUserId(u), name: u.fullName, email: u.email }));
      const primary = task.primaryAssigneeId == null ? null : dict.get(String(task.primaryAssigneeId));
      return res.json({ assignees, primaryAssigneeId: primary ? publicUserId(primary) : null });
    } catch (error) { return error500(res, error); }
  });

  router.put('/:id/assignees', auth, async (req, res) => {
    try {
      const task = await Task.findOne({
        ...idFilter(req.params.id), createdBy: req.user._id
      });
      if (!task) return res.status(403).json({ message: 'Chỉ người tạo được giao việc.' });

      const ids = req.body?.userIds;
      if (!Array.isArray(ids) || ids.length > 30 || ids.some(id => typeof id !== 'string' || !id)) {
        return res.status(400).json({ message: 'Danh sách người được giao không hợp lệ (tối đa 30).' });
      }
      if (new Set(ids).size !== ids.length) {
        return res.status(400).json({ message: 'Người được giao bị trùng.' });
      }
      if (ids.includes(req.user.id) || ids.includes(String(req.user._id))) {
        return res.status(400).json({ message: 'Người tạo không cần tự giao việc cho mình.' });
      }
      const objectIds = ids.filter(id => /^[\da-f]{24}$/i.test(id))
        .map(id => new mongoose.Types.ObjectId(id));
      const users = ids.length ? await User.find({
        $or: [{ legacyId: { $in: ids } }, { _id: { $in: objectIds } }]
      }).lean() : [];
      const byPublicId = new Map(users.map(u => [publicUserId(u), u]));
      const byMongoId = new Map(users.map(u => [String(u._id), u]));
      const assignees = ids.map(id => byPublicId.get(id) || byMongoId.get(id));
      if (assignees.some(u => !u)) {
        return res.status(400).json({ message: 'Có tài khoản không tồn tại.' });
      }
      if (new Set(assignees.map(u => String(u._id))).size !== assignees.length) {
        return res.status(400).json({ message: 'Người được giao bị trùng.' });
      }
      if (assignees.some(u => String(u._id) === String(req.user._id))) {
        return res.status(400).json({ message: 'Người tạo không cần tự giao việc cho mình.' });
      }
      task.assigneeIds = assignees.map(u => u._id);
      if (task.primaryAssigneeId && !task.assigneeIds.some(id => String(id) === String(task.primaryAssigneeId))) {
        task.primaryAssigneeId = null;
      }
      await task.save();
      return res.json({ message: 'Giao việc thành công.', task: await clientTask(task) });
    } catch (error) { return error500(res, error); }
  });

  // C3: Lay danh sach nguoi duoc chia se. Nguoi co quyen doc cong viec duoc xem.
  router.get('/:id/shares', auth, async (req, res) => {
    try {
      const task = await taskForRequest(req.params.id, req.user._id);
      if (!task) {
        return res.status(404).json({ message: 'Khong tim thay cong viec hoac ban khong co quyen truy cap.' });
      }

      const records = await TaskShare.find({ taskId: task._id })
        .sort({ createdAt: 1 }).lean();
      const recipientIds = records.map(share => share.userId);
      const recipients = recipientIds.length
        ? await User.find({ _id: { $in: recipientIds } }).lean()
        : [];
      const userById = new Map(recipients.map(user => [String(user._id), user]));
      const shares = records.map(share => {
        const recipient = userById.get(String(share.userId));
        return {
          id: String(share._id),
          userId: recipient ? publicUserId(recipient) : String(share.userId),
          name: recipient?.fullName || '',
          email: recipient?.email || '',
          permission: share.permission,
          createdAt: new Date(share.createdAt).toISOString()
        };
      });
      return res.json({ shares, total: shares.length, canManage: canManageTask(task, req.user._id) });
    } catch (error) { return error500(res, error); }
  });

  // C3: Chu cong viec chia se theo email. C3 chi cap quyen xem (viewer).
  // C4 se bo sung quyen editor va chinh sach cap nhat noi dung.
  router.post('/:id/shares', auth, async (req, res) => {
    try {
      const task = await Task.findOne({
        ...idFilter(req.params.id), createdBy: req.user._id
      }).lean();
      if (!task) {
        return res.status(403).json({ message: 'Chi nguoi tao cong viec duoc phep chia se.' });
      }

      const email = typeof req.body?.email === 'string'
        ? req.body.email.trim().toLowerCase()
        : '';
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254) {
        return res.status(400).json({ message: 'Email chia se khong hop le.' });
      }

      const recipient = await User.findOne({ email }).lean();
      if (!recipient) {
        return res.status(404).json({ message: 'Khong tim thay tai khoan nhan chia se.' });
      }
      if (String(recipient._id) === String(req.user._id)) {
        return res.status(400).json({ message: 'Ban khong can chia se cho chinh minh.' });
      }

      const existing = await TaskShare.exists({ taskId: task._id, userId: recipient._id });
      if (existing) {
        return res.status(409).json({ message: 'Cong viec da duoc chia se cho tai khoan nay.' });
      }

      const share = await TaskShare.create({
        taskId: task._id,
        userId: recipient._id,
        sharedBy: req.user._id,
        permission: 'viewer'
      });
      return res.status(201).json({
        message: 'Chia se cong viec thanh cong.',
        share: {
          id: String(share._id),
          userId: publicUserId(recipient),
          name: recipient.fullName,
          email: recipient.email,
          permission: share.permission,
          createdAt: share.createdAt.toISOString()
        }
      });
    } catch (error) {
      if (error?.code === 11000) {
        return res.status(409).json({ message: 'Cong viec da duoc chia se cho tai khoan nay.' });
      }
      return error500(res, error);
    }
  });

  // C2: Set or clear the primary assignee.
  // Only the task creator can perform this action.
  router.patch('/:id/primary-assignee', auth, async (req, res) => {
    try {
      const body = req.body || {};

      if (!Object.prototype.hasOwnProperty.call(body, 'userId')) {
        return res.status(400).json({
          message: 'userId is required.'
        });
      }

      const task = await Task.findOne({
        ...idFilter(req.params.id),
        createdBy: req.user._id
      });

      if (!task) {
        return res.status(403).json({
          message: 'Only the task creator can set the primary assignee.'
        });
      }

      if (body.userId === null) {
        task.primaryAssigneeId = null;
      } else {
        if (typeof body.userId !== 'string' || !body.userId.trim()) {
          return res.status(400).json({
            message: 'Invalid userId.'
          });
        }

        const assignees = await User.find({
          _id: { $in: task.assigneeIds || [] }
        }).lean();

        const selected = assignees.find(user =>
          publicUserId(user) === body.userId.trim() ||
          String(user._id) === body.userId.trim()
        );

        if (!selected) {
          return res.status(400).json({
            message: 'Primary assignee must be an assigned member.'
          });
        }

        task.primaryAssigneeId = selected._id;
      }

      await task.save();

      return res.json({
        message: 'Primary assignee updated successfully.',
        task: await clientTask(task)
      });
    } catch (error) {
      return error500(res, error);
    }
  });
  return router;
};
