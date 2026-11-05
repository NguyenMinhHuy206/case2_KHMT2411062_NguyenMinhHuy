'use strict';
const express = require('express');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

module.exports = function createTaskRouter(auth) {
  const router = express.Router();
  const DB = path.join(__dirname, 'tasks.json');

  function readTasks() {
    if (!fs.existsSync(DB)) return [];
    const raw = fs.readFileSync(DB, 'utf8').replace(/^\uFEFF/, '').trim();
    const tasks = raw ? JSON.parse(raw) : [];
    if (!Array.isArray(tasks)) throw new Error('tasks.json must contain an array');
    return tasks;
  }
  function saveTasks(tasks) {
    const temp = DB + '.tmp';
    fs.writeFileSync(temp, JSON.stringify(tasks, null, 2), 'utf8');
    fs.renameSync(temp, DB);
  }
  function validDate(date) {
    if (date === null) return true;
    if (typeof date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(date)) return false;
    const d = new Date(`${date}T00:00:00.000Z`);
    return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === date;
  }
  function validateFields(body) {
    const title = typeof body.title === 'string' ? body.title.trim() : '';
    const description = body.description === undefined || body.description === null ? '' : body.description;
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
  function error500(res, error) {
    console.error(error);
    return res.status(500).json({ message: 'Lỗi máy chủ.' });
  }
  function ownTask(req, res) {
    const task = readTasks().find(t => t.id === req.params.id);
    if (!task || task.createdBy !== req.user.id) {
      res.status(404).json({ message: 'Không tìm thấy công việc hoặc bạn không có quyền truy cập.' });
      return null;
    }
    return task;
  }

  // B1: Danh sách công việc do người dùng tạo.
  router.get('/', auth, (req, res) => {
    try {
      const tasks = readTasks()
        .filter(t => t.createdBy === req.user.id)
        .sort((a, b) => String(b.createdAt ?? '').localeCompare(String(a.createdAt ?? '')));
      return res.json({ total: tasks.length, tasks });
    } catch (error) { return error500(res, error); }
  });

  // B2: Tạo công việc.
  router.post('/', auth, (req, res) => {
    try {
      const check = validateFields(req.body || {});
      if (check.error) return res.status(400).json({ message: check.error });
      const now = new Date().toISOString();
      const task = {
        id: crypto.randomUUID(), ...check.fields,
        createdBy: req.user.id, createdAt: now, updatedAt: now
      };
      const tasks = readTasks();
      tasks.push(task);
      saveTasks(tasks);
      return res.status(201).json({ message: 'Tạo công việc thành công.', task });
    } catch (error) { return error500(res, error); }
  });

  // B2: Xem chi tiết.
  router.get('/:id', auth, (req, res) => {
    try {
      const task = ownTask(req, res);
      if (!task) return;
      return res.json({ task });
    } catch (error) { return error500(res, error); }
  });

  // B2: Chỉnh sửa. Thay thế bộ trường có thể chỉnh sửa, giữ nguyên ID và chủ sở hữu.
  router.put('/:id', auth, (req, res) => {
    try {
      const tasks = readTasks();
      const index = tasks.findIndex(t => t.id === req.params.id && t.createdBy === req.user.id);
      if (index < 0) return res.status(404).json({ message: 'Không tìm thấy công việc hoặc bạn không có quyền chỉnh sửa.' });
      const check = validateFields({ ...tasks[index], ...(req.body || {}) });
      if (check.error) return res.status(400).json({ message: check.error });
      const task = { ...tasks[index], ...check.fields, updatedAt: new Date().toISOString() };
      tasks[index] = task;
      saveTasks(tasks);
      return res.json({ message: 'Cập nhật công việc thành công.', task });
    } catch (error) { return error500(res, error); }
  });

  // B3: Cap nhat rieng trang thai. Chi nguoi tao duoc doi trang thai.
  router.patch('/:id/status', auth, (req, res) => {
    try {
      const status = req.body?.status;
      if (!['pending', 'in_progress', 'completed'].includes(status)) {
        return res.status(400).json({ message: 'Trang thai khong hop le.' });
      }
      const tasks = readTasks();
      const index = tasks.findIndex(t => t.id === req.params.id && t.createdBy === req.user.id);
      if (index < 0) {
        return res.status(404).json({ message: 'Khong tim thay cong viec hoac ban khong co quyen cap nhat.' });
      }
      const updated = { ...tasks[index], status, updatedAt: new Date().toISOString() };
      tasks[index] = updated;
      saveTasks(tasks);
      return res.json({ message: 'Cap nhat trang thai thanh cong.', task: updated });
    } catch (error) { return error500(res, error); }
  });

  // B4: Cap nhat rieng muc do uu tien (low / medium / high).
  router.patch('/:id/priority', auth, (req, res) => {
    try {
      const priority = req.body?.priority;
      if (!['low', 'medium', 'high'].includes(priority)) {
        return res.status(400).json({ message: 'Muc do uu tien khong hop le.' });
      }
      const tasks = readTasks();
      const index = tasks.findIndex(t => t.id === req.params.id && t.createdBy === req.user.id);
      if (index < 0) {
        return res.status(404).json({ message: 'Khong tim thay cong viec hoac ban khong co quyen cap nhat.' });
      }
      const updated = { ...tasks[index], priority, updatedAt: new Date().toISOString() };
      tasks[index] = updated;
      saveTasks(tasks);
      return res.json({ message: 'Cap nhat muc do uu tien thanh cong.', task: updated });
    } catch (error) { return error500(res, error); }
  });

  // B5: Cap nhat ngay bat dau va han hoan thanh; kiem tra JWT, chu so huu, thu tu ngay.
  router.patch('/:id/dates', auth, (req, res) => {
    try {
      const body = req.body || {};
      if (!Object.prototype.hasOwnProperty.call(body, 'startDate') ||
          !Object.prototype.hasOwnProperty.call(body, 'dueDate')) {
        return res.status(400).json({ message: 'Can gui startDate va dueDate (YYYY-MM-DD hoac null).' });
      }
      const tasks = readTasks();
      const index = tasks.findIndex(t => t.id === req.params.id && t.createdBy === req.user.id);
      if (index < 0) {
        return res.status(404).json({ message: 'Khong tim thay cong viec hoac ban khong co quyen cap nhat.' });
      }
      const check = validateFields({ ...tasks[index], startDate: body.startDate, dueDate: body.dueDate });
      if (check.error) return res.status(400).json({ message: check.error });
      const updated = {
        ...tasks[index],
        startDate: check.fields.startDate,
        dueDate: check.fields.dueDate,
        updatedAt: new Date().toISOString()
      };
      tasks[index] = updated;
      saveTasks(tasks);
      return res.json({ message: 'Cap nhat ngay bat dau va han hoan thanh thanh cong.', task: updated });
    } catch (error) { return error500(res, error); }
  });
  // B2: Xóa, chỉ chủ sở hữu được phép thao tác.
  router.delete('/:id', auth, (req, res) => {
    try {
      const tasks = readTasks();
      const index = tasks.findIndex(t => t.id === req.params.id && t.createdBy === req.user.id);
      if (index < 0) return res.status(404).json({ message: 'Không tìm thấy công việc hoặc bạn không có quyền xóa.' });
      tasks.splice(index, 1);
      saveTasks(tasks);
      return res.json({ message: 'Xóa công việc thành công.' });
    } catch (error) { return error500(res, error); }
  });

  return router;
};
