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
    if (!token) return res.status(401).json({message:'Báº¡n chÆ°a Ä‘Äƒng nháº­p.'});
    const decoded = jwt.verify(token, SECRET);
    const user = readUsers().find(u=>u.id===decoded.sub);
    if (!user || (user.tokenVersion||0)!==(decoded.ver||0)) return res.status(401).json({message:'PhiÃªn Ä‘Äƒng nháº­p khÃ´ng há»£p lá»‡.'});
    req.user = user;
    next();
  } catch(e) {return res.status(401).json({message:'PhiÃªn Ä‘Äƒng nháº­p háº¿t háº¡n hoáº·c khÃ´ng há»£p lá»‡.'});}
}
function tokenFor(user) {return jwt.sign({sub:user.id,ver:user.tokenVersion||0}, SECRET, {expiresIn:'7d'});}
app.get('/health',(req,res)=>res.json({status:'ok'}));
app.post('/register',async(req,res)=>{
  try {
    const name=String(req.body.name||'').trim(); const email=emailOf(req.body.email); const password=String(req.body.password||'');
    if(name.length<2||!validEmail(email)||password.length<6) return res.status(400).json({message:'Há» tÃªn tá»‘i thiá»ƒu 2 kÃ½ tá»±, email há»£p lá»‡ vÃ  máº­t kháº©u tá»‘i thiá»ƒu 6 kÃ½ tá»±.'});
    const users=readUsers(); if(users.some(u=>u.email===email)) return res.status(409).json({message:'Email Ä‘Ã£ Ä‘Æ°á»£c Ä‘Äƒng kÃ½.'});
    const user={id:crypto.randomUUID(),name,email,passwordHash:await bcrypt.hash(password,12),tokenVersion:0};
    users.push(user); saveUsers(users);
    return res.status(201).json({message:'ÄÄƒng kÃ½ thÃ nh cÃ´ng.',user:cleanUser(user),token:tokenFor(user)});
  } catch(e) {console.error(e);return res.status(500).json({message:'Lá»—i mÃ¡y chá»§.'});}
});
app.post('/login',async(req,res)=>{
  try {
    const email=emailOf(req.body.email); const password=String(req.body.password||'');
    const user=readUsers().find(u=>u.email===email);
    if(!user||!(await bcrypt.compare(password,user.passwordHash))) return res.status(401).json({message:'Email hoáº·c máº­t kháº©u khÃ´ng Ä‘Ãºng.'});
    return res.json({message:'ÄÄƒng nháº­p thÃ nh cÃ´ng.',user:cleanUser(user),token:tokenFor(user)});
  } catch(e) {console.error(e);return res.status(500).json({message:'Lá»—i mÃ¡y chá»§.'});}
});
app.get('/me',auth,(req,res)=>res.json({user:cleanUser(req.user)}));
app.put('/me',auth,(req,res)=>{
  try {
    const name=String(req.body.name||'').trim(); const email=emailOf(req.body.email);
    if(name.length<2||!validEmail(email)) return res.status(400).json({message:'Há» tÃªn hoáº·c email khÃ´ng há»£p lá»‡.'});
    const users=readUsers();
    if(users.some(u=>u.id!==req.user.id&&u.email===email)) return res.status(409).json({message:'Email Ä‘Ã£ Ä‘Æ°á»£c sá»­ dá»¥ng.'});
    const user=users.find(u=>u.id===req.user.id); user.name=name;user.email=email;saveUsers(users);
    return res.json({message:'Cáº­p nháº­t thÃ´ng tin thÃ nh cÃ´ng.',user:cleanUser(user)});
  } catch(e) {console.error(e);return res.status(500).json({message:'Lá»—i mÃ¡y chá»§.'});}
});
app.put('/change-password',auth,async(req,res)=>{
  try {
    const oldPassword=String(req.body.oldPassword||'');const newPassword=String(req.body.newPassword||'');
    if(newPassword.length<6)return res.status(400).json({message:'Máº­t kháº©u má»›i pháº£i cÃ³ Ã­t nháº¥t 6 kÃ½ tá»±.'});
    if(!(await bcrypt.compare(oldPassword,req.user.passwordHash)))return res.status(400).json({message:'Máº­t kháº©u hiá»‡n táº¡i khÃ´ng Ä‘Ãºng.'});
    if(oldPassword===newPassword)return res.status(400).json({message:'Máº­t kháº©u má»›i pháº£i khÃ¡c máº­t kháº©u cÅ©.'});
    const users=readUsers();const user=users.find(u=>u.id===req.user.id);
    user.passwordHash=await bcrypt.hash(newPassword,12);user.tokenVersion=(user.tokenVersion||0)+1;saveUsers(users);
    return res.json({message:'Äá»•i máº­t kháº©u thÃ nh cÃ´ng. Vui lÃ²ng Ä‘Äƒng nháº­p láº¡i.'});
  } catch(e){console.error(e);return res.status(500).json({message:'Lá»—i mÃ¡y chá»§.'});}
});
app.post('/logout',auth,(req,res)=>{
  try {
    const users=readUsers();const user=users.find(u=>u.id===req.user.id);
    user.tokenVersion=(user.tokenVersion||0)+1;saveUsers(users);
    return res.json({message:'ÄÄƒng xuáº¥t thÃ nh cÃ´ng.'});
  } catch(e){console.error(e);return res.status(500).json({message:'Lá»—i mÃ¡y chá»§.'});}
});
app.use('/api/tasks', require('./taskRoutes')(auth));
app.listen(PORT,'0.0.0.0',()=>console.log(`Server running at http://localhost:${PORT}`));

