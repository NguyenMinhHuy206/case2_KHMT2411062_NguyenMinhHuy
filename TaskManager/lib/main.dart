import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() { WidgetsFlutterBinding.ensureInitialized(); runApp(const TaskManagerApp()); }

class Api {
  static const base = 'http://10.0.2.2:3000'; // Android Emulator -> Windows localhost
  static String? token;
  static Future<Map<String, dynamic>> request(String method, String path, [Map<String, dynamic>? body]) async {
    try {
      final uri = Uri.parse('$base$path');
      final headers = <String,String>{'Content-Type':'application/json',if(token!=null)'Authorization':'Bearer $token'};
      late http.Response response;
      if(method=='GET') {response=await http.get(uri,headers:headers).timeout(const Duration(seconds:12));}
      else if(method=='PUT') {response=await http.put(uri,headers:headers,body:jsonEncode(body??{})).timeout(const Duration(seconds:12));}
      else {response=await http.post(uri,headers:headers,body:jsonEncode(body??{})).timeout(const Duration(seconds:12));}
      final data=jsonDecode(response.body);
      if(data is! Map<String,dynamic>) throw Exception('Phản hồi từ máy chủ không hợp lệ.');
      if(response.statusCode>=400) throw Exception(data['message']?.toString()??'Yêu cầu thất bại (${response.statusCode}).');
      return data;
    } catch(e) {
      if(e is FormatException) throw Exception('Phản hồi từ máy chủ không đúng định dạng.');
      if(e is Exception && e.toString().startsWith('Exception:')) rethrow;
      throw Exception('Không kết nối được Backend. Kiểm tra Node.js đang chạy ở cổng 3000.');
    }
  }
  static Future<void> saveToken(String value) async {
    token=value;
    final prefs=await SharedPreferences.getInstance();
    await prefs.setString('auth_token',value);
  }
  static Future<void> clearToken() async {
    token=null;
    final prefs=await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
  }
}

class TaskManagerApp extends StatelessWidget {
  const TaskManagerApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    title:'Task Manager',debugShowCheckedModeBanner:false,
    theme:ThemeData(useMaterial3:true,colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xFF6D9DE6)),scaffoldBackgroundColor:const Color(0xFFFAFBFE),inputDecorationTheme:InputDecorationTheme(border:OutlineInputBorder(borderRadius:BorderRadius.circular(12)),contentPadding:const EdgeInsets.symmetric(horizontal:14,vertical:16))),
    home:const AuthGateway(),
  );
}

class AuthGateway extends StatefulWidget {
  const AuthGateway({super.key});
  @override State<AuthGateway> createState()=>_AuthGatewayState();
}
class _AuthGatewayState extends State<AuthGateway> {
  bool loading=true;
  bool loggedIn=false;
  @override void initState(){super.initState();restore();}
  Future<void> restore()async{
    final prefs=await SharedPreferences.getInstance();
    Api.token=prefs.getString('auth_token');
    bool ok=false;
    if(Api.token!=null){try{await Api.request('GET','/me');ok=true;}catch(_){await Api.clearToken();}}
    if(mounted)setState((){loggedIn=ok;loading=false;});
  }
  void goHome()=>setState(()=>loggedIn=true);
  void goLogin()=>setState(()=>loggedIn=false);
  @override Widget build(BuildContext context)=>loading?const Scaffold(body:Center(child:CircularProgressIndicator())):
    loggedIn?HomeScreen(onLogout:goLogin):LoginScreen(onSuccess:goHome);
}

class AuthLayout extends StatelessWidget {
  final String title,subtitle;
  final List<Widget> children;
  const AuthLayout({super.key,required this.title,required this.subtitle,required this.children});
  @override Widget build(BuildContext context)=>Scaffold(body:SafeArea(child:Center(child:SingleChildScrollView(padding:const EdgeInsets.symmetric(horizontal:28,vertical:28),child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:400),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Center(child:CircleAvatar(radius:30,backgroundColor:const Color(0xFFE8F1FF),child:Icon(Icons.task_alt_rounded,size:34,color:Theme.of(context).colorScheme.primary))),
    const SizedBox(height:22),Text(title,textAlign:TextAlign.center,style:const TextStyle(fontSize:25,fontWeight:FontWeight.bold)),
    const SizedBox(height:7),Text(subtitle,textAlign:TextAlign.center,style:const TextStyle(color:Colors.black54)),
    const SizedBox(height:34),...children,
  ]))))));
}

class LoginScreen extends StatefulWidget {
  final VoidCallback onSuccess;
  const LoginScreen({super.key,required this.onSuccess});
  @override State<LoginScreen> createState()=>_LoginScreenState();
}
class _LoginScreenState extends State<LoginScreen> {
  final formKey=GlobalKey<FormState>();
  final email=TextEditingController(),password=TextEditingController();
  bool busy=false,hide=true;
  @override void dispose(){email.dispose();password.dispose();super.dispose();}
  Future<void> submit()async{
    if(!formKey.currentState!.validate())return;
    setState(()=>busy=true);
    try{
      final data=await Api.request('POST','/login',{'email':email.text.trim(),'password':password.text});
      await Api.saveToken(data['token'] as String);
      if(mounted)widget.onSuccess();
    }catch(e){if(mounted)showError(context,e);}finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>AuthLayout(title:'Đăng nhập',subtitle:'Chào mừng bạn quay lại Task Manager',children:[
    Form(key:formKey,child:Column(children:[
      TextFormField(controller:email,keyboardType:TextInputType.emailAddress,decoration:const InputDecoration(labelText:'Email',prefixIcon:Icon(Icons.mail_outline)),validator:(v)=>v==null||!v.contains('@')?'Nhập email hợp lệ':null),
      const SizedBox(height:14),TextFormField(controller:password,obscureText:hide,decoration:InputDecoration(labelText:'Mật khẩu',prefixIcon:const Icon(Icons.lock_outline),suffixIcon:IconButton(icon:Icon(hide?Icons.visibility_outlined:Icons.visibility_off_outlined),onPressed:()=>setState(()=>hide=!hide))),validator:(v)=>v==null||v.isEmpty?'Vui lòng nhập mật khẩu':null),
      const SizedBox(height:20),FilledButton(onPressed:busy?null:submit,child:Padding(padding:const EdgeInsets.all(13),child:Text(busy?'Đang đăng nhập...':'Đăng nhập'))),
    ])),const SizedBox(height:14),TextButton(onPressed:busy?null:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const RegisterScreen())),child:const Text('Chưa có tài khoản? Đăng ký ngay')),
  ]);
}

class RegisterScreen extends StatefulWidget {const RegisterScreen({super.key});@override State<RegisterScreen> createState()=>_RegisterScreenState();}
class _RegisterScreenState extends State<RegisterScreen> {
  final keyForm=GlobalKey<FormState>();
  final name=TextEditingController(),email=TextEditingController(),password=TextEditingController(),confirm=TextEditingController();
  bool busy=false,hide=true;
  @override void dispose(){name.dispose();email.dispose();password.dispose();confirm.dispose();super.dispose();}
  Future<void> submit()async{
    if(!keyForm.currentState!.validate())return;
    setState(()=>busy=true);
    try{
      await Api.request('POST','/register',{'name':name.text.trim(),'email':email.text.trim(),'password':password.text});
      if(!mounted)return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Đăng ký thành công! Hãy đăng nhập.')));
      Navigator.pop(context);
    }catch(e){if(mounted)showError(context,e);}finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>AuthLayout(title:'Tạo tài khoản',subtitle:'Bắt đầu quản lý công việc cùng Task Manager',children:[
    Form(key:keyForm,child:Column(children:[
      TextFormField(controller:name,decoration:const InputDecoration(labelText:'Họ và tên',prefixIcon:Icon(Icons.person_outline)),validator:(v)=>(v??'').trim().length<2?'Nhập họ tên ít nhất 2 ký tự':null),
      const SizedBox(height:13),TextFormField(controller:email,keyboardType:TextInputType.emailAddress,decoration:const InputDecoration(labelText:'Email',prefixIcon:Icon(Icons.mail_outline)),validator:(v)=>v==null||!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v.trim())?'Email không hợp lệ':null),
      const SizedBox(height:13),TextFormField(controller:password,obscureText:hide,decoration:InputDecoration(labelText:'Mật khẩu',prefixIcon:const Icon(Icons.lock_outline),suffixIcon:IconButton(onPressed:()=>setState(()=>hide=!hide),icon:Icon(hide?Icons.visibility_outlined:Icons.visibility_off_outlined))),validator:(v)=>(v??'').length<6?'Tối thiểu 6 ký tự':null),
      const SizedBox(height:13),TextFormField(controller:confirm,obscureText:hide,decoration:const InputDecoration(labelText:'Xác nhận mật khẩu',prefixIcon:Icon(Icons.verified_user_outlined)),validator:(v)=>v!=password.text?'Mật khẩu xác nhận không khớp':null),
      const SizedBox(height:17),SizedBox(width:double.infinity,child:FilledButton(onPressed:busy?null:submit,child:Padding(padding:const EdgeInsets.all(13),child:Text(busy?'Đang tạo tài khoản...':'Đăng ký tài khoản')))),
    ])),const SizedBox(height:12),TextButton(onPressed:busy?null:()=>Navigator.pop(context),child:const Text('Đã có tài khoản? Đăng nhập')),
  ]);
}

class HomeScreen extends StatefulWidget {final VoidCallback onLogout;const HomeScreen({super.key,required this.onLogout});@override State<HomeScreen> createState()=>_HomeScreenState();}
class _HomeScreenState extends State<HomeScreen> {
  Map<String,dynamic>? user;
  bool loading=true;
  @override void initState(){super.initState();load();}
  Future<void> load()async{
    try{final d=await Api.request('GET','/me');if(mounted)setState((){user=d['user'] as Map<String,dynamic>;loading=false;});}
    catch(e){if(mounted){showError(context,e);await Api.clearToken();widget.onLogout();}}
  }
  Future<void> logout()async{
    try{await Api.request('POST','/logout');}catch(_){/* Clear local token even if offline */}
    await Api.clearToken();if(mounted)widget.onLogout();
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Task Manager'),actions:[IconButton(tooltip:'Đăng xuất',onPressed:logout,icon:const Icon(Icons.logout))]),body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(22),children:[
    const Icon(Icons.account_circle_outlined,size:82,color:Color(0xFF6D9DE6)),const SizedBox(height:12),
    Text('Xin chào, ${user?['name']??''}!',textAlign:TextAlign.center,style:const TextStyle(fontSize:23,fontWeight:FontWeight.bold)),
    const SizedBox(height:8),Text('${user?['email']??''}',textAlign:TextAlign.center),const SizedBox(height:32),
    Card(child:ListTile(leading:const Icon(Icons.person_outline),title:const Text('Xem và cập nhật thông tin cá nhân'),trailing:const Icon(Icons.chevron_right),onTap:()async{await Navigator.push(context,MaterialPageRoute(builder:(_)=>const ProfileScreen()));load();})),
    Card(child:ListTile(leading:const Icon(Icons.key_outlined),title:const Text('Đổi mật khẩu'),trailing:const Icon(Icons.chevron_right),onTap:()async{final changed=await Navigator.push<bool>(context,MaterialPageRoute(builder:(_)=>const PasswordScreen()));if(changed==true){await Api.clearToken();if(context.mounted)widget.onLogout();}})),
    const SizedBox(height:16),OutlinedButton.icon(onPressed:logout,icon:const Icon(Icons.logout),label:const Text('Đăng xuất')),
  ]));
}

class ProfileScreen extends StatefulWidget {const ProfileScreen({super.key});@override State<ProfileScreen> createState()=>_ProfileScreenState();}
class _ProfileScreenState extends State<ProfileScreen> {
  final form=GlobalKey<FormState>();final name=TextEditingController(),email=TextEditingController();bool busy=true;
  @override void initState(){super.initState();load();}
  @override void dispose(){name.dispose();email.dispose();super.dispose();}
  Future<void> load()async{try{final d=await Api.request('GET','/me');name.text=d['user']['name'];email.text=d['user']['email'];}catch(e){if(mounted)showError(context,e);}finally{if(mounted)setState(()=>busy=false);}}
  Future<void> save()async{if(!form.currentState!.validate())return;setState(()=>busy=true);try{await Api.request('PUT','/me',{'name':name.text.trim(),'email':email.text.trim()});if(mounted){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Đã cập nhật thông tin.')));Navigator.pop(context);}}catch(e){if(mounted)showError(context,e);}finally{if(mounted)setState(()=>busy=false);}}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Thông tin cá nhân')),body:busy&&name.text.isEmpty?const Center(child:CircularProgressIndicator()):SingleChildScrollView(padding:const EdgeInsets.all(22),child:Form(key:form,child:Column(children:[
    TextFormField(controller:name,decoration:const InputDecoration(labelText:'Họ và tên',prefixIcon:Icon(Icons.person_outline)),validator:(v)=>(v??'').trim().length<2?'Họ tên tối thiểu 2 ký tự':null),const SizedBox(height:16),
    TextFormField(controller:email,keyboardType:TextInputType.emailAddress,decoration:const InputDecoration(labelText:'Email',prefixIcon:Icon(Icons.email_outlined)),validator:(v)=>v==null||!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v.trim())?'Email không hợp lệ':null),const SizedBox(height:22),
    SizedBox(width:double.infinity,child:FilledButton(onPressed:busy?null:save,child:const Text('Lưu thay đổi'))),
  ]))));
}

class PasswordScreen extends StatefulWidget {const PasswordScreen({super.key});@override State<PasswordScreen> createState()=>_PasswordScreenState();}
class _PasswordScreenState extends State<PasswordScreen> {
  final form=GlobalKey<FormState>();final oldPass=TextEditingController(),newPass=TextEditingController(),confirm=TextEditingController();bool busy=false,hide=true;
  @override void dispose(){oldPass.dispose();newPass.dispose();confirm.dispose();super.dispose();}
  Future<void> save()async{if(!form.currentState!.validate())return;setState(()=>busy=true);try{
    await Api.request('PUT','/change-password',{'oldPassword':oldPass.text,'newPassword':newPass.text});
    if(mounted){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Đổi mật khẩu thành công. Vui lòng đăng nhập lại.')));Navigator.pop(context,true);}
  }catch(e){if(mounted)showError(context,e);}finally{if(mounted)setState(()=>busy=false);}}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Đổi mật khẩu')),body:SingleChildScrollView(padding:const EdgeInsets.all(22),child:Form(key:form,child:Column(children:[
    TextFormField(controller:oldPass,obscureText:hide,decoration:const InputDecoration(labelText:'Mật khẩu hiện tại',prefixIcon:Icon(Icons.lock_outline)),validator:(v)=>(v??'').isEmpty?'Vui lòng nhập mật khẩu hiện tại':null),const SizedBox(height:15),
    TextFormField(controller:newPass,obscureText:hide,decoration:const InputDecoration(labelText:'Mật khẩu mới',prefixIcon:Icon(Icons.lock_reset)),validator:(v)=>(v??'').length<6?'Tối thiểu 6 ký tự':null),const SizedBox(height:15),
    TextFormField(controller:confirm,obscureText:hide,decoration:const InputDecoration(labelText:'Xác nhận mật khẩu mới',prefixIcon:Icon(Icons.verified_user_outlined)),validator:(v)=>v!=newPass.text?'Mật khẩu không khớp':null),const SizedBox(height:8),
    SwitchListTile(title:const Text('Hiện mật khẩu'),value:!hide,onChanged:(v)=>setState(()=>hide=!v)),const SizedBox(height:20),
    SizedBox(width:double.infinity,child:FilledButton(onPressed:busy?null:save,child:Text(busy?'Đang xử lý...':'Đổi mật khẩu'))),
  ]))));
}
void showError(BuildContext context,Object error){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(error.toString().replaceFirst('Exception: ','')),backgroundColor:Colors.red.shade700));}
