
const express = require('express');
const { randomBytes, scrypt, timingSafeEqual } = require('node:crypto');
const { promisify } = require('node:util');

const app = express();
const PORT = 3000;
const scryptAsync = promisify(scrypt);

app.use(express.json());

const users = [];

app.get('/', (req, res) => {
  res.json({ message: 'TaskManager API running' });
});

// Chức năng đăng ký tài khoản
app.post('/api/register', async (req, res) => {
  try {
    const { name, email, password } = req.body || {};

    if (
      typeof name !== 'string' ||
      typeof email !== 'string' ||
      typeof password !== 'string'
    ) {
      return res.status(400).json({
        message: 'Vui lòng nhập đầy đủ thông tin'
      });
    }

    const cleanName = name.trim();
    const cleanEmail = email.trim().toLowerCase();

    if (!cleanName || !cleanEmail || !password) {
      return res.status(400).json({
        message: 'Vui lòng nhập đầy đủ thông tin'
      });
    }

    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(cleanEmail)) {
      return res.status(400).json({
        message: 'Email không hợp lệ'
      });
    }

    if (password.length < 8) {
      return res.status(400).json({
        message: 'Mật khẩu phải có ít nhất 8 ký tự'
      });
    }

    if (users.some(user => user.email === cleanEmail)) {
      return res.status(409).json({
        message: 'Email đã được đăng ký'
      });
    }

    const salt = randomBytes(16).toString('hex');
    const hash = (await scryptAsync(password, salt, 64))
      .toString('hex');

    const user = {
      id: users.length + 1,
      name: cleanName,
      email: cleanEmail,
      passwordHash: `${salt}:${hash}`
    };

    users.push(user);

    return res.status(201).json({
      message: 'Đăng ký thành công',
      user: {
        id: user.id,
        name: user.name,
        email: user.email
      }
    });
  } catch (error) {
    console.error(error);
    return res.status(500).json({
      message: 'Lỗi máy chủ'
    });
  }
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running at http://localhost:${PORT}`);
});
