'use strict';
const express = require('express');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const app = express();
app.use(cors());
app.use(express.json({limit:'20kb'}));
const PORT = process.env.PORT || 3000;
const SECRET = process.env.JWT_SECRET || 'LOCAL_DEVELOPMENT_ONLY_CHANGE_ME_BEFORE_DEPLOY';
if (SECRET === 'LOCAL_DEVELOPMENT_ONLY_CHANGE_ME_BEFORE_DEPLOY') {
  console.warn('WARNING: JWT_SECRET is not configured. Local development only.');
}
const DB = path.join(__dirname, 'users.json');
function readUsers() {
  if (!fs.existsSync(DB)) return [];
  return JSON.parse(fs.readFileSync(DB,'utf8'));
}
function saveUsers(users) {
  const tmp = DB + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(users,null,2));
  fs.renameSync(tmp, DB);
}
function cleanUser(user) {return {id:user.id,name:user.name,email:user.email};}
function emailOf(value) {return String(value||'').trim().toLowerCase();}
function validEmail(email) {return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);}
function auth(req,res,next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : '';
  try {
    if (!token) return res.status(401).json({message:'Bạn chưa đăng nhập.'});
    const decoded = jwt.verify(token, SECRET);
    const user = readUsers().find(u=>u.id===decoded.sub);
    if (!user || (user.tokenVersion||0)!==(decoded.ver||0)) return res.status(401).json({message:'Phiên đăng nhập không hợp lệ.'});
    req.user = user;
    next();
  } catch(e) {return res.status(401).json({message:'Phiên đăng nhập hết hạn hoặc không hợp lệ.'});}
}
function tokenFor(user) {return jwt.sign({sub:user.id,ver:user.tokenVersion||0}, SECRET, {expiresIn:'7d'});}
app.get('/health',(req,res)=>res.json({status:'ok'}));
app.post('/register',async(req,res)=>{
  try {
    const name=String(req.body.name||'').trim(); const email=emailOf(req.body.email); const password=String(req.body.password||'');
    if(name.length<2||!validEmail(email)||password.length<6) return res.status(400).json({message:'Họ tên tối thiểu 2 ký tự, email hợp lệ và mật khẩu tối thiểu 6 ký tự.'});
    const users=readUsers(); if(users.some(u=>u.email===email)) return res.status(409).json({message:'Email đã được đăng ký.'});
    const user={id:crypto.randomUUID(),name,email,passwordHash:await bcrypt.hash(password,12),tokenVersion:0};
    users.push(user); saveUsers(users);
    return res.status(201).json({message:'Đăng ký thành công.',user:cleanUser(user),token:tokenFor(user)});
  } catch(e) {console.error(e);return res.status(500).json({message:'Lỗi máy chủ.'});}
});
app.post('/login',async(req,res)=>{
  try {
    const email=emailOf(req.body.email); const password=String(req.body.password||'');
    const user=readUsers().find(u=>u.email===email);
    if(!user||!(await bcrypt.compare(password,user.passwordHash))) return res.status(401).json({message:'Email hoặc mật khẩu không đúng.'});
    return res.json({message:'Đăng nhập thành công.',user:cleanUser(user),token:tokenFor(user)});
  } catch(e) {console.error(e);return res.status(500).json({message:'Lỗi máy chủ.'});}
});
app.get('/me',auth,(req,res)=>res.json({user:cleanUser(req.user)}));
app.put('/me',auth,(req,res)=>{
  try {
    const name=String(req.body.name||'').trim(); const email=emailOf(req.body.email);
    if(name.length<2||!validEmail(email)) return res.status(400).json({message:'Họ tên hoặc email không hợp lệ.'});
    const users=readUsers();
    if(users.some(u=>u.id!==req.user.id&&u.email===email)) return res.status(409).json({message:'Email đã được sử dụng.'});
    const user=users.find(u=>u.id===req.user.id); user.name=name;user.email=email;saveUsers(users);
    return res.json({message:'Cập nhật thông tin thành công.',user:cleanUser(user)});
  } catch(e) {console.error(e);return res.status(500).json({message:'Lỗi máy chủ.'});}
});
app.put('/change-password',auth,async(req,res)=>{
  try {
    const oldPassword=String(req.body.oldPassword||'');const newPassword=String(req.body.newPassword||'');
    if(newPassword.length<6)return res.status(400).json({message:'Mật khẩu mới phải có ít nhất 6 ký tự.'});
    if(!(await bcrypt.compare(oldPassword,req.user.passwordHash)))return res.status(400).json({message:'Mật khẩu hiện tại không đúng.'});
    if(oldPassword===newPassword)return res.status(400).json({message:'Mật khẩu mới phải khác mật khẩu cũ.'});
    const users=readUsers();const user=users.find(u=>u.id===req.user.id);
    user.passwordHash=await bcrypt.hash(newPassword,12);user.tokenVersion=(user.tokenVersion||0)+1;saveUsers(users);
    return res.json({message:'Đổi mật khẩu thành công. Vui lòng đăng nhập lại.'});
  } catch(e){console.error(e);return res.status(500).json({message:'Lỗi máy chủ.'});}
});
app.post('/logout',auth,(req,res)=>{
  try {
    const users=readUsers();const user=users.find(u=>u.id===req.user.id);
    user.tokenVersion=(user.tokenVersion||0)+1;saveUsers(users);
    return res.json({message:'Đăng xuất thành công.'});
  } catch(e){console.error(e);return res.status(500).json({message:'Lỗi máy chủ.'});}
});
app.listen(PORT,'0.0.0.0',()=>console.log(`Server running at http://localhost:${PORT}`));
