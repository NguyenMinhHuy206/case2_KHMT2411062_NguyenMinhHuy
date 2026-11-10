'use strict';

const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });

const express = require('express');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { connectDatabase, mongoose } = require('./config/database');
const User = require('./models/User');

const app = express();
app.use(cors());
app.use(express.json({ limit: '20kb' }));

const PORT = Number(process.env.PORT || 3000);
const SECRET = process.env.JWT_SECRET;

// Khong su dung khoa JWT mac dinh co the doan duoc.
if (!SECRET || SECRET.length < 32) {
  console.error('JWT_SECRET chua duoc cau hinh (toi thieu 32 ky tu) trong api/.env.');
  process.exit(1);
}

function publicId(user) {
  return user.legacyId || String(user._id);
}

function cleanUser(user) {
  return { id: publicId(user), name: user.fullName, email: user.email };
}

function emailOf(value) {
  return String(value || '').trim().toLowerCase();
}

function validEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

function userIdQuery(id) {
  const query = [{ legacyId: String(id) }];
  if (/^[\da-f]{24}$/i.test(String(id))) {
    query.push({ _id: new mongoose.Types.ObjectId(String(id)) });
  }
  return { $or: query };
}

async function auth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : '';
  if (!token) return res.status(401).json({ message: 'Bạn chưa đăng nhập.' });

  let decoded;
  try {
    decoded = jwt.verify(token, SECRET);
  } catch (_) {
    return res.status(401).json({ message: 'Phiên đăng nhập hết hạn hoặc không hợp lệ.' });
  }

  try {
    if (typeof decoded.sub !== 'string' || !decoded.sub) {
      return res.status(401).json({ message: 'Phiên đăng nhập không hợp lệ.' });
    }
    const user = await User.findOne(userIdQuery(decoded.sub));
    if (!user || (user.tokenVersion || 0) !== (decoded.ver || 0)) {
      return res.status(401).json({ message: 'Phiên đăng nhập không hợp lệ.' });
    }
    req.dbUser = user;
    req.user = { id: publicId(user), _id: user._id };
    return next();
  } catch (error) {
    console.error('AUTH_DATABASE_ERROR:', error);
    return res.status(503).json({ message: 'Không thể xác thực do lỗi kết nối cơ sở dữ liệu.' });
  }
}

function tokenFor(user) {
  return jwt.sign(
    { sub: publicId(user), ver: user.tokenVersion || 0 },
    SECRET,
    { expiresIn: '7d' }
  );
}

function serverError(res, error) {
  console.error(error);
  return res.status(500).json({ message: 'Lỗi máy chủ.' });
}

app.get('/health', (req, res) => res.json({ status: 'ok' }));

// Giu nguyen endpoint Flutter da su dung: /register, /login, /me, ...
app.post('/register', async (req, res) => {
  try {
    const name = String(req.body?.name || '').trim();
    const email = emailOf(req.body?.email);
    const password = String(req.body?.password || '');
    if (name.length < 2 || !validEmail(email) || password.length < 6) {
      return res.status(400).json({ message: 'Họ tên tối thiểu 2 ký tự, email hợp lệ và mật khẩu tối thiểu 6 ký tự.' });
    }
    if (await User.exists({ email })) {
      return res.status(409).json({ message: 'Email đã được đăng ký.' });
    }
    const user = await User.create({
      fullName: name, email, passwordHash: await bcrypt.hash(password, 12), tokenVersion: 0
    });
    return res.status(201).json({ message: 'Đăng ký thành công.', user: cleanUser(user), token: tokenFor(user) });
  } catch (error) {
    if (error?.code === 11000) return res.status(409).json({ message: 'Email đã được đăng ký.' });
    return serverError(res, error);
  }
});

app.post('/login', async (req, res) => {
  try {
    const email = emailOf(req.body?.email);
    const password = String(req.body?.password || '');
    const user = await User.findOne({ email });
    if (!user || !(await bcrypt.compare(password, user.passwordHash))) {
      return res.status(401).json({ message: 'Email hoặc mật khẩu không đúng.' });
    }
    return res.json({ message: 'Đăng nhập thành công.', user: cleanUser(user), token: tokenFor(user) });
  } catch (error) {
    return serverError(res, error);
  }
});

app.get('/me', auth, (req, res) => res.json({ user: cleanUser(req.dbUser) }));

app.put('/me', auth, async (req, res) => {
  try {
    const name = String(req.body?.name || '').trim();
    const email = emailOf(req.body?.email);
    if (name.length < 2 || !validEmail(email)) {
      return res.status(400).json({ message: 'Họ tên hoặc email không hợp lệ.' });
    }
    if (await User.exists({ email, _id: { $ne: req.dbUser._id } })) {
      return res.status(409).json({ message: 'Email đã được sử dụng.' });
    }
    req.dbUser.fullName = name;
    req.dbUser.email = email;
    await req.dbUser.save();
    return res.json({ message: 'Cập nhật thông tin thành công.', user: cleanUser(req.dbUser) });
  } catch (error) {
    if (error?.code === 11000) return res.status(409).json({ message: 'Email đã được sử dụng.' });
    return serverError(res, error);
  }
});

app.put('/change-password', auth, async (req, res) => {
  try {
    const oldPassword = String(req.body?.oldPassword || '');
    const newPassword = String(req.body?.newPassword || '');
    if (newPassword.length < 6) {
      return res.status(400).json({ message: 'Mật khẩu mới phải có ít nhất 6 ký tự.' });
    }
    if (!(await bcrypt.compare(oldPassword, req.dbUser.passwordHash))) {
      return res.status(400).json({ message: 'Mật khẩu hiện tại không đúng.' });
    }
    if (oldPassword === newPassword) {
      return res.status(400).json({ message: 'Mật khẩu mới phải khác mật khẩu cũ.' });
    }
    req.dbUser.passwordHash = await bcrypt.hash(newPassword, 12);
    req.dbUser.tokenVersion = (req.dbUser.tokenVersion || 0) + 1;
    await req.dbUser.save();
    return res.json({ message: 'Đổi mật khẩu thành công. Vui lòng đăng nhập lại.' });
  } catch (error) {
    return serverError(res, error);
  }
});

app.post('/logout', auth, async (req, res) => {
  try {
    req.dbUser.tokenVersion = (req.dbUser.tokenVersion || 0) + 1;
    await req.dbUser.save();
    return res.json({ message: 'Đăng xuất thành công.' });
  } catch (error) {
    return serverError(res, error);
  }
});

app.use('/api/tasks', require('./taskRoutes')(auth));
app.use('/api/notifications', require('./d7Notifications')(auth));
app.use('/api/statistics', require('./e1Statistics')(auth));
app.use('/api/statistics', require('./e2Statistics')(auth));
const { startDueReminderScheduler } = require('./d5Reminder');

// Chi mo cong sau khi MongoDB ket noi thanh cong.
connectDatabase()
  .then(() => {
    startDueReminderScheduler();
    app.listen(PORT, '0.0.0.0', () => {
      console.log(`Server running at http://localhost:${PORT} (MongoDB)`);
    });
  })
  .catch(error => {
    console.error('MONGODB_START_FAILED:', error.message);
    process.exitCode = 1;
  });
