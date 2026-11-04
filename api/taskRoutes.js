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
    const content = fs.readFileSync(DB, 'utf8').replace(/^\uFEFF/, '').trim();
    return content ? JSON.parse(content) : [];
  }

  function saveTasks(tasks) {
    const temp = DB + '.tmp';
    fs.writeFileSync(temp, JSON.stringify(tasks, null, 2), 'utf8');
    fs.renameSync(temp, DB);
  }

  router.post('/', auth, (req, res) => {
    try {
      const title = String(req.body.title || '').trim();
      const description = String(req.body.description || '').trim();
      const status = req.body.status || 'pending';
      const priority = req.body.priority || 'medium';
      const startDate = req.body.startDate || null;
      const dueDate = req.body.dueDate || null;

      if (!title || title.length > 200) {
        return res.status(400).json({
          message: 'Tieu de phai co tu 1 den 200 ky tu.'
        });
      }

      if (!['pending', 'in_progress', 'completed'].includes(status)) {
        return res.status(400).json({
          message: 'Trang thai khong hop le.'
        });
      }

      if (!['low', 'medium', 'high'].includes(priority)) {
        return res.status(400).json({
          message: 'Do uu tien khong hop le.'
        });
      }

      for (const value of [startDate, dueDate]) {
        if (value !== null && (typeof value !== 'string' ||
            !/^\d{4}-\d{2}-\d{2}$/.test(value) ||
            Number.isNaN(Date.parse(value)))) {
          return res.status(400).json({
            message: 'Ngay phai dung dinh dang YYYY-MM-DD.'
          });
        }
      }

      if (startDate && dueDate && startDate > dueDate) {
        return res.status(400).json({
          message: 'Han hoan thanh phai sau ngay bat dau.'
        });
      }

      const task = {
        id: crypto.randomUUID(),
        title,
        description,
        status,
        priority,
        startDate,
        dueDate,
        createdBy: req.user.id,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString()
      };

      const tasks = readTasks();
      tasks.push(task);
      saveTasks(tasks);

      return res.status(201).json({
        message: 'Tao cong viec thanh cong.',
        task
      });
    } catch (error) {
      console.error(error);
      return res.status(500).json({
        message: 'Loi may chu.'
      });
    }
  });

  router.get('/', auth, (req, res) => {
    try {
      const tasks = readTasks()
        .filter(task => task.createdBy === req.user.id)
        .sort((a, b) => b.createdAt.localeCompare(a.createdAt));

      return res.json({
        total: tasks.length,
        tasks
      });
    } catch (error) {
      console.error(error);
      return res.status(500).json({
        message: 'Khong the lay danh sach cong viec.'
      });
    }
  });

  return router;
};
