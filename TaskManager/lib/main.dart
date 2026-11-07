// UI_REFRESH_V1: Chi thay doi giao dien, giu nguyen API va B1-B6.
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
      else if(method=='PATCH') {response=await http.patch(uri,headers:headers,body:jsonEncode(body??{})).timeout(const Duration(seconds:12));}
      else if(method=='DELETE') {response=await http.delete(uri,headers:headers).timeout(const Duration(seconds:12));}
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
  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF3867D6);
    const ink = Color(0xFF18243D);
    const background = Color(0xFFF5F7FC);
    final scheme = ColorScheme.fromSeed(seedColor: blue, brightness: Brightness.light);
    return MaterialApp(
      title: 'Task Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: background,
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: background,
          foregroundColor: ink,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: ink),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFE6EBF4)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFDFE5F0)),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: blue, foregroundColor: Colors.white,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      home: const AuthGateway(),
    );
  }
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
  final String title, subtitle;
  final List<Widget> children;
  const AuthLayout({super.key, required this.title, required this.subtitle, required this.children});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                height: 112,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3867D6), Color(0xFF829BF3)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Center(
                  child: Icon(Icons.task_alt_rounded, color: Colors.white, size: 53),
                ),
              ),
              const SizedBox(height: 24),
              Text(title, style: const TextStyle(
                fontSize: 27, fontWeight: FontWeight.w800, color: Color(0xFF18243D),
              )),
              const SizedBox(height: 6),
              Text(subtitle, style: const TextStyle(color: Color(0xFF6D7891), fontSize: 14)),
              const SizedBox(height: 24),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFE5EAF3)),
                ),
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
              ),
              const SizedBox(height: 20),
              const Text('TASK MANAGER  •  CASE STUDY 2',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF98A2B7), letterSpacing: 1, fontSize: 10)),
            ]),
          ),
        ),
      ),
    ),
  );
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

class HomeScreen extends StatefulWidget {
  final VoidCallback onLogout;
  const HomeScreen({super.key, required this.onLogout});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? user;
  bool loading = true;
  List<dynamic>? taskItems;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final response = await Api.request('GET', '/me');
      if (!mounted) return;
      setState(() {
        user = response['user'] as Map<String, dynamic>;
        loading = false;
      });
      await reloadStats();
    } catch (e) {
      if (!mounted) return;
      showError(context, e);
      await Api.clearToken();
      if (mounted) widget.onLogout();
    }
  }

  Future<void> reloadStats() async {
    try {
      final result = await Api.request('GET', '/api/tasks');
      final items = result['tasks'];
      if (mounted) setState(() => taskItems = items is List ? items : null);
    } catch (_) {
      if (mounted) setState(() => taskItems = null);
    }
  }

  Future<void> logout() async {
    try { await Api.request('POST', '/logout'); } catch (_) { /* offline logout */ }
    await Api.clearToken();
    if (mounted) widget.onLogout();
  }

  Future<void> openTasks() async {
    await Navigator.push(context,
      MaterialPageRoute(builder: (_) => const TaskListScreen()));
    if (mounted) await reloadStats();
  }

  Future<void> openCreate() async {
    final created = await Navigator.push<bool>(context,
      MaterialPageRoute(builder: (_) => const CreateTaskScreen()));
    if (!mounted) return;
    if (created == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã tạo công việc thành công.')));
    }
    await reloadStats();
  }

  Future<void> openProfile() async {
    await Navigator.push(context,
      MaterialPageRoute(builder: (_) => const ProfileScreen()));
    if (mounted) await load();
  }

  Future<void> openPassword() async {
    final changed = await Navigator.push<bool>(context,
      MaterialPageRoute(builder: (_) => const PasswordScreen()));
    if (changed == true) {
      await Api.clearToken();
      if (mounted) widget.onLogout();
    }
  }

  Widget metric(String label, int? count, IconData icon, Color tone) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6EBF4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: tone, size: 23),
        const SizedBox(height: 12),
        Text(count?.toString() ?? '—', style: const TextStyle(
          fontSize: 25, fontWeight: FontWeight.w800, color: Color(0xFF18243D))),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF697891))),
      ]),
    ));
  }

  Widget actionTile(String title, String subtitle, IconData icon, Color color, VoidCallback action) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: action,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: color, size: 23),
            ),
            const SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1C2941))),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF7B879C))),
            ])),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF9AA7BB)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = taskItems;
    final total = items?.length;
    final active = items?.where((t) => t is Map && t['status'] == 'in_progress').length;
    final completed = items?.where((t) => t is Map && t['status'] == 'completed').length;
    final displayName = (user?['name'] ?? 'Bạn').toString();

    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.task_alt_rounded, color: Color(0xFF3867D6)),
          SizedBox(width: 9),
          Text('TaskManager'),
        ]),
        actions: [
          IconButton(tooltip: 'Làm mới thống kê', onPressed: reloadStats,
            icon: const Icon(Icons.refresh_rounded)),
          IconButton(tooltip: 'Đăng xuất', onPressed: logout,
            icon: const Icon(Icons.logout_rounded)),
        ],
      ),
      body: loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
          onRefresh: reloadStats,
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 14, 20, 30), children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF3867D6), Color(0xFF728BE7)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('CHÀO MỪNG TRỞ LẠI', style: TextStyle(
                    color: Color(0xFFDDE7FF), fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Text('Xin chào, $displayName!',
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text((user?['email'] ?? '').toString(), maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFFE1E9FF), fontSize: 12)),
                ])),
                const SizedBox(width: 12),
                const CircleAvatar(radius: 28,
                  backgroundColor: Color(0x33FFFFFF),
                  child: Icon(Icons.person_rounded, color: Colors.white, size: 30)),
              ]),
            ),
            const SizedBox(height: 24),
            const Text('Tổng quan công việc', style: TextStyle(
              color: Color(0xFF18243D), fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 5),
            const Text('Dữ liệu thực từ công việc do bạn tạo',
              style: TextStyle(color: Color(0xFF768399), fontSize: 12)),
            const SizedBox(height: 14),
            Row(children: [
              metric('Tổng công việc', total, Icons.library_books_outlined, const Color(0xFF3867D6)),
              const SizedBox(width: 9),
              metric('Đang làm', active, Icons.hourglass_top_rounded, const Color(0xFFF3A442)),
              const SizedBox(width: 9),
              metric('Hoàn thành', completed, Icons.check_circle_outline, const Color(0xFF27A879)),
            ]),
            const SizedBox(height: 26),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Thao tác nhanh', style: TextStyle(
                color: Color(0xFF18243D), fontWeight: FontWeight.w800, fontSize: 18)),
              TextButton(onPressed: openTasks, child: const Text('Xem tất cả')),
            ]),
            const SizedBox(height: 4),
            actionTile('Danh sách công việc', 'Xem, tìm kiếm và lọc công việc',
              Icons.view_list_rounded, const Color(0xFF3867D6), openTasks),
            actionTile('Tạo công việc mới', 'Thêm công việc vào hệ thống',
              Icons.add_task_rounded, const Color(0xFF27A879), openCreate),
            actionTile('Thông tin cá nhân', 'Xem và cập nhật hồ sơ',
              Icons.manage_accounts_outlined, const Color(0xFF7868C9), openProfile),
            actionTile('Đổi mật khẩu', 'Bảo mật tài khoản của bạn',
              Icons.lock_outline_rounded, const Color(0xFFE7A23B), openPassword),
            const SizedBox(height: 12),
            TextButton.icon(onPressed: logout,
              icon: const Icon(Icons.logout_rounded), label: const Text('Đăng xuất')),
          ]),
        ),
    );
  }
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
// B1 – Tao cong viec; su dung Api.request va JWT da co trong phan A.
class CreateTaskScreen extends StatefulWidget {
  const CreateTaskScreen({super.key});

  @override
  State<CreateTaskScreen> createState() => _CreateTaskScreenState();
}

class _CreateTaskScreenState extends State<CreateTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  String _status = 'pending';
  String _priority = 'medium';
  DateTime? _startDate;
  DateTime? _dueDate;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate({required bool start}) async {
    final current = start ? _startDate : _dueDate;
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: start ? 'Chọn ngày bắt đầu' : 'Chọn hạn hoàn thành',
    );
    if (picked != null && mounted) {
      setState(() {
        if (start) {
          _startDate = picked;
        } else {
          _dueDate = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate != null &&
        _dueDate != null &&
        _dueDate!.isBefore(_startDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hạn hoàn thành phải từ ngày bắt đầu trở đi.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await Api.request('POST', '/api/tasks', {
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        'status': _status,
        'priority': _priority,
        'startDate': _startDate == null ? null : _formatDate(_startDate!),
        'dueDate': _dueDate == null ? null : _formatDate(_dueDate!),
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Tạo công việc mới')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Thông tin công việc',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text('Điền thông tin bên dưới để tạo công việc.'),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _title,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: 'Tiêu đề *',
                      prefixIcon: Icon(Icons.assignment_outlined),
                    ),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'Vui lòng nhập tiêu đề công việc'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _description,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Mô tả',
                      alignLabelWithHint: true,
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: const InputDecoration(
                      labelText: 'Trạng thái',
                      prefixIcon: Icon(Icons.track_changes_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'pending', child: Text('Chưa thực hiện')),
                      DropdownMenuItem(value: 'in_progress', child: Text('Đang thực hiện')),
                      DropdownMenuItem(value: 'completed', child: Text('Đã hoàn thành')),
                    ],
                    onChanged: _saving ? null : (value) {
                      if (value != null) setState(() => _status = value);
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _priority,
                    decoration: const InputDecoration(
                      labelText: 'Độ ưu tiên',
                      prefixIcon: Icon(Icons.flag_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'low', child: Text('Thấp')),
                      DropdownMenuItem(value: 'medium', child: Text('Trung bình')),
                      DropdownMenuItem(value: 'high', child: Text('Cao')),
                    ],
                    onChanged: _saving ? null : (value) {
                      if (value != null) setState(() => _priority = value);
                    },
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : () => _pickDate(start: true),
                    icon: const Icon(Icons.event_outlined),
                    label: Text(_startDate == null
                        ? 'Chọn ngày bắt đầu'
                        : 'Ngày bắt đầu: ${_formatDate(_startDate!)}'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : () => _pickDate(start: false),
                    icon: const Icon(Icons.event_available_outlined),
                    label: Text(_dueDate == null
                        ? 'Chọn hạn hoàn thành'
                        : 'Hạn hoàn thành: ${_formatDate(_dueDate!)}'),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_saving ? 'Đang lưu...' : 'Tạo công việc'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

}

// B1: Danh sach cong viec do tai khoan dang nhap tao.
// Cong viec duoc giao/nhan/chia se can dong bo voi phan C.
class TaskListScreen extends StatefulWidget {
  const TaskListScreen({super.key});

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _tasks = [];
  // B6: Search and combined filters for already authorized task list.
  final TextEditingController _search = TextEditingController();
  String _statusFilter = 'all';
  String _priorityFilter = 'all';
  // B7_SORT_V1: sort filtered tasks, keeping missing due dates last.
  String _sortMode = 'created_newest';
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }
  List<Map<String, dynamic>> get _visibleTasks {
    final keyword = _search.text.trim().toLowerCase();
    final items = _tasks.where((task) {
      final title = (task['title'] ?? '').toString().toLowerCase();
      final matchesTitle = keyword.isEmpty || title.contains(keyword);
      final matchesStatus = _statusFilter == 'all' || task['status'] == _statusFilter;
      final matchesPriority = _priorityFilter == 'all' || task['priority'] == _priorityFilter;
      return matchesTitle && matchesStatus && matchesPriority;
    }).toList();

    int priorityScore(dynamic p) {
      switch (p?.toString()) {
        case 'high': return 3;
        case 'medium': return 2;
        case 'low': return 1;
        default: return 0;
      }
    }
    DateTime? parsed(dynamic value) {
      final s = value?.toString().trim() ?? '';
      return s.isEmpty ? null : DateTime.tryParse(s);
    }
    int compareDate(dynamic a, dynamic b, {required bool ascending, bool missingLast = false}) {
      final da = parsed(a), db = parsed(b);
      if (missingLast) {
        if (da == null && db != null) return 1;
        if (da != null && db == null) return -1;
      }
      if (da == null && db == null) return 0;
      if (da == null) return ascending ? -1 : 1;
      if (db == null) return ascending ? 1 : -1;
      return ascending ? da.compareTo(db) : db.compareTo(da);
    }
    items.sort((a, b) {
      int result;
      switch (_sortMode) {
        case 'due_asc':
          result = compareDate(a['dueDate'], b['dueDate'], ascending: true, missingLast: true);
          break;
        case 'due_desc':
          result = compareDate(a['dueDate'], b['dueDate'], ascending: false, missingLast: true);
          break;
        case 'priority_high':
          result = priorityScore(b['priority']).compareTo(priorityScore(a['priority']));
          break;
        case 'priority_low':
          result = priorityScore(a['priority']).compareTo(priorityScore(b['priority']));
          break;
        case 'created_oldest':
          result = compareDate(a['createdAt'], b['createdAt'], ascending: true);
          break;
        case 'created_newest':
        default:
          result = compareDate(a['createdAt'], b['createdAt'], ascending: false);
          break;
      }
      if (result != 0) return result;
      // Consistent tie order across refreshes.
      return (a['id'] ?? '').toString().compareTo((b['id'] ?? '').toString());
    });
    return items;
  }

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final response = await Api.request('GET', '/api/tasks');
      final raw = response['tasks'];
      if (raw is! List) {
        throw Exception('Danh sách công việc trả về không hợp lệ.');
      }
      final items = raw
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (!mounted) return;
      setState(() { _tasks = items; _loading = false; });
    } catch (error) {
      if (!mounted) return;
      setState(() { _error = error.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending': return 'Chưa thực hiện';
      case 'in_progress': return 'Đang thực hiện';
      case 'completed': return 'Đã hoàn thành';
      default: return 'Không xác định';
    }
  }

  String _priorityLabel(String priority) {
    switch (priority) {
      case 'low': return 'Thấp';
      case 'medium': return 'Trung bình';
      case 'high': return 'Cao';
      default: return 'Chưa xác định';
    }
  }

  String _formatDate(dynamic value) {
    if (value == null || value.toString().isEmpty) return 'Chưa đặt hạn';
    final date = DateTime.tryParse(value.toString());
    if (date == null) return 'Không hợp lệ';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year}';
  }

  Future<void> _openCreate() async {
    final created = await Navigator.push<bool>(
      context, MaterialPageRoute(builder: (_) => const CreateTaskScreen()),
    );
    if (!mounted) return;
    if (created == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã tạo công việc thành công.')),
      );
      await _loadTasks();
    }
  }

  Future<void> _openDetail(Map<String, dynamic> task) async {
    final id = (task['id'] ?? '').toString();
    if (id.isEmpty) { showError(context, 'Công việc chưa có ID hợp lệ.'); return; }
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => TaskDetailScreen(taskId: id),
    ));
    if (mounted) await _loadTasks();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Danh sách công việc'),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            onPressed: _loading ? null : _loadTasks,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.add),
        label: const Text('Tạo công việc'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _loadTasks, child: const Text('Thử lại')),
                    ]),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadTasks,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    children: [
                      Text('Công việc do bạn tạo: ${_tasks.length}',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      const Text('Công việc được giao, nhận và chia sẻ sẽ được tích hợp ở phần C.',
                          style: TextStyle(color: Colors.black54)),
                      const SizedBox(height: 18),
                       // B6: Search title and filter by status/priority.
                       TextField(
                         controller: _search,
                         onChanged: (_) => setState(() {}),
                         decoration: InputDecoration(
                           labelText: 'Tìm theo tên công việc',
                           hintText: 'Nhập tên công việc...',
                           prefixIcon: const Icon(Icons.search),
                           suffixIcon: _search.text.isEmpty ? null : IconButton(
                             tooltip: 'Xóa tìm kiếm',
                             icon: const Icon(Icons.clear),
                             onPressed: () { _search.clear(); setState(() {}); },
                           ),
                         ),
                       ),
                       const SizedBox(height: 12),
                       DropdownButtonFormField<String>(
                         initialValue: _statusFilter,
                         decoration: const InputDecoration(labelText: 'Lọc theo trạng thái'),
                         items: const [
                           DropdownMenuItem(value:'all', child:Text('Tất cả trạng thái')),
                           DropdownMenuItem(value:'pending', child:Text('Chưa thực hiện')),
                           DropdownMenuItem(value:'in_progress', child:Text('Đang thực hiện')),
                           DropdownMenuItem(value:'completed', child:Text('Đã hoàn thành')),
                         ],
                         onChanged: (v) { if(v != null) setState(() => _statusFilter = v); },
                       ),
                       const SizedBox(height: 12),
                       DropdownButtonFormField<String>(
                         initialValue: _priorityFilter,
                         decoration: const InputDecoration(labelText: 'Lọc theo ưu tiên'),
                         items: const [
                           DropdownMenuItem(value:'all', child:Text('Tất cả mức ưu tiên')),
                           DropdownMenuItem(value:'low', child:Text('Thấp')),
                           DropdownMenuItem(value:'medium', child:Text('Trung bình')),
                           DropdownMenuItem(value:'high', child:Text('Cao')),
                         ],
                         onChanged: (v) { if(v != null) setState(() => _priorityFilter = v); },
                       ),
                       const SizedBox(height: 8),
                                 // B7_SORT_V1: ordering applies after B6 search and filters.
          DropdownButtonFormField<String>(
            key: ValueKey('B7_$_sortMode'),
            initialValue: _sortMode,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'B7 - Sắp xếp công việc',
              prefixIcon: Icon(Icons.sort),
            ),
            items: const [
              DropdownMenuItem(value: 'due_asc', child: Text('Hạn hoàn thành: gần nhất')),
              DropdownMenuItem(value: 'due_desc', child: Text('Hạn hoàn thành: xa nhất')),
              DropdownMenuItem(value: 'priority_high', child: Text('Ưu tiên: Cao → Thấp')),
              DropdownMenuItem(value: 'priority_low', child: Text('Ưu tiên: Thấp → Cao')),
              DropdownMenuItem(value: 'created_newest', child: Text('Thời gian tạo: mới nhất')),
              DropdownMenuItem(value: 'created_oldest', child: Text('Thời gian tạo: cũ nhất')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _sortMode = value);
            },
          ),
          const SizedBox(height: 12),
const Text('Người phụ trách: sẽ bổ sung khi hoàn thành phần C.',
                           style: TextStyle(color: Colors.black54, fontSize: 12)),
                       const SizedBox(height: 8),
                       OutlinedButton.icon(
                         onPressed: () => setState(() {
                           _search.clear();
                           _statusFilter = 'all';
                           _priorityFilter = 'all';
          _sortMode = 'created_newest';
                         }),
                         icon: const Icon(Icons.filter_alt_off_outlined),
                         label: const Text('Xóa bộ lọc'),
                       ),
                       const SizedBox(height: 12),
                       Text('Hiển thị: ${_visibleTasks.length}/${_tasks.length} công việc'),
                       const SizedBox(height: 10),
                       if (_visibleTasks.isEmpty)
                        const Card(child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: Text('Chưa có công việc nào.')),
                        )),
                       for (final task in _visibleTasks)
                        Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => _openDetail(task),
                            child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text((task['title'] ?? 'Không có tiêu đề').toString(),
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                if ((task['description'] ?? '').toString().trim().isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(task['description'].toString(),
                                      maxLines: 2, overflow: TextOverflow.ellipsis),
                                ],
                                const SizedBox(height: 10),
                                Wrap(spacing: 8, runSpacing: 6, children: [
                                  Chip(label: Text(_statusLabel((task['status'] ?? '').toString()))),
                                  Chip(label: Text('Ưu tiên: ${_priorityLabel((task['priority'] ?? '').toString())}')),
                                ]),
                                const SizedBox(height: 6),
                                Text('Hạn hoàn thành: ${_formatDate(task['dueDate'])}',
                                    style: const TextStyle(color: Colors.black54)),
                                const SizedBox(height: 8),
                                const Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                                  Text('Xem chi tiết', style: TextStyle(color: Color(0xFF416DAF))),
                                  SizedBox(width: 4), Icon(Icons.chevron_right, size: 18),
                                ]),
                              ],
                            ),
                          ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}


// B2: Chi tiết công việc và các thao tác chỉnh sửa, xóa.
class TaskDetailScreen extends StatefulWidget {
  final String taskId;
  const TaskDetailScreen({super.key, required this.taskId});
  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  Map<String, dynamic>? _task;
  String? _error;
  bool _loading = true;
  bool _deleting = false;
  bool _updatingStatus = false;
  bool _updatingPriority = false;
  bool _updatingDates = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final response = await Api.request('GET', '/api/tasks/${widget.taskId}');
      if (!mounted) return;
      setState(() { _task = Map<String, dynamic>.from(response['task'] as Map); _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  String _status(String v) => switch (v) {
    'pending' => 'Chưa thực hiện',
    'in_progress' => 'Đang thực hiện',
    'completed' => 'Đã hoàn thành',
    _ => 'Không xác định',
  };
  String _priority(String v) => switch (v) {
    'low' => 'Thấp', 'medium' => 'Trung bình', 'high' => 'Cao', _ => 'Chưa xác định',
  };
  String _date(dynamic v) {
    final raw = (v ?? '').toString();
    if (raw.isEmpty) return 'Chưa thiết lập';
    final d = DateTime.tryParse(raw);
    if (d == null) return 'Ngày không hợp lệ';
    String two(int x) => x.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }
  Widget _item(String label, String value, IconData icon) => ListTile(
    leading: Icon(icon, color: const Color(0xFF416DAF)),
    title: Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
    subtitle: Text(value, style: const TextStyle(fontSize: 15, color: Colors.black87)),
  );

  // B3: Thay doi trang thai ngay tai man hinh chi tiet, khong can sua toan bo form.
  Future<void> _changeStatus(String nextStatus) async {
    if (_task == null || _updatingStatus || _updatingPriority || _deleting) return;
    if (nextStatus == (_task!['status'] ?? '').toString()) return;
    setState(() => _updatingStatus = true);
    try {
      final response = await Api.request(
        'PATCH', '/api/tasks/${widget.taskId}/status', {'status': nextStatus},
      );
      if (!mounted) return;
      setState(() => _task = Map<String, dynamic>.from(response['task'] as Map));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cập nhật trạng thái thành công.')),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _updatingStatus = false);
    }
  }

  // B4: Cap nhat muc do uu tien ngay tai man hinh chi tiet.
  Future<void> _changePriority(String nextPriority) async {
    if (_task == null || _updatingPriority || _updatingStatus || _deleting) return;
    if (nextPriority == (_task!['priority'] ?? '').toString()) return;
    setState(() => _updatingPriority = true);
    try {
      final response = await Api.request(
        'PATCH', '/api/tasks/${widget.taskId}/priority', {'priority': nextPriority},
      );
      if (!mounted) return;
      setState(() => _task = Map<String, dynamic>.from(response['task'] as Map));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cập nhật mức độ ưu tiên thành công.')),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _updatingPriority = false);
    }
  }

  // B5 - Thiet lap ngay bat dau va han hoan thanh tren man hinh chi tiet.
  String _b5Iso(DateTime? date) {
    if (date == null) { return ''; }
    String pad(int x) => x.toString().padLeft(2, '0');
    return '${date.year}-${pad(date.month)}-${pad(date.day)}';
  }
  Future<void> _changeDates() async {
    if (_task == null || _updatingDates || _updatingPriority || _updatingStatus || _deleting) { return; }
    DateTime? start = DateTime.tryParse((_task!['startDate'] ?? '').toString());
    DateTime? due = DateTime.tryParse((_task!['dueDate'] ?? '').toString());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, updateDialog) => AlertDialog(
          title: const Text('B5 - Thiết lập thời gian'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: const Text('Ngày bắt đầu'),
              subtitle: Text(start == null ? 'Chưa đặt' : _date(_b5Iso(start))),
              onTap: () async {
                final picked = await showDatePicker(
                  context: dialogContext,
                  initialDate: start ?? DateTime.now(),
                  firstDate: DateTime(2000), lastDate: DateTime(2100),
                );
                if (picked != null) { updateDialog(() => start = picked); }
              },
              trailing: IconButton(
                tooltip: 'Bỏ ngày bắt đầu',
                onPressed: () => updateDialog(() => start = null),
                icon: const Icon(Icons.clear),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: const Text('Hạn hoàn thành'),
              subtitle: Text(due == null ? 'Chưa đặt' : _date(_b5Iso(due))),
              onTap: () async {
                final picked = await showDatePicker(
                  context: dialogContext,
                  initialDate: due ?? start ?? DateTime.now(),
                  firstDate: DateTime(2000), lastDate: DateTime(2100),
                );
                if (picked != null) { updateDialog(() => due = picked); }
              },
              trailing: IconButton(
                tooltip: 'Bỏ hạn hoàn thành',
                onPressed: () => updateDialog(() => due = null),
                icon: const Icon(Icons.clear),
              ),
            ),
            const Text('Hạn hoàn thành không được trước ngày bắt đầu.'),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Hủy')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Lưu ngày')),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) { return; }
    if (start != null && due != null && due!.isBefore(start!)) {
      showError(context, 'Hạn hoàn thành phải từ ngày bắt đầu trở đi.');
      return;
    }
    setState(() => _updatingDates = true);
    try {
      final response = await Api.request('PATCH', '/api/tasks/${widget.taskId}/dates', {
        'startDate': start == null ? null : _b5Iso(start),
        'dueDate': due == null ? null : _b5Iso(due),
      });
      if (!mounted) { return; }
      setState(() => _task = Map<String, dynamic>.from(response['task'] as Map));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cập nhật ngày thành công.')),
      );
    } catch (e) {
      if (mounted) { showError(context, e); }
    } finally {
      if (mounted) { setState(() => _updatingDates = false); }
    }
  }
  Future<void> _edit() async {
    if (_task == null) return;
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => EditTaskScreen(task: _task!),
    ));
    if (changed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cập nhật công việc thành công.')));
      await _load();
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa công việc?'),
        content: const Text('Công việc sẽ bị xóa vĩnh viễn. Bạn có chắc chắn muốn xóa?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Xóa')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await Api.request('DELETE', '/api/tasks/${widget.taskId}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã xóa công việc.')));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Chi tiết công việc'), actions: [
      IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh), tooltip: 'Làm mới'),
    ]),
    body: _loading ? const Center(child: CircularProgressIndicator())
      : _error != null ? Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Thử lại')),
          ]),
        ))
      : _task == null ? const Center(child: Text('Không tìm thấy công việc.'))
      : SingleChildScrollView(padding: const EdgeInsets.all(18), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text((_task!['title'] ?? '').toString(),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Card(child: Column(children: [
              _item('Mô tả', (_task!['description'] ?? '').toString().isEmpty ? 'Không có mô tả' : _task!['description'].toString(), Icons.notes),
              _item('Trạng thái', _status((_task!['status'] ?? '').toString()), Icons.track_changes),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                child: DropdownButtonFormField<String>(
                  key: ValueKey('b3_status_${_task!['status']}'),
                  initialValue: (_task!['status'] ?? 'pending').toString(),
                  decoration: const InputDecoration(
                    labelText: 'B3 - Cập nhật trạng thái',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.sync_alt),
                    helperText: 'Chọn trạng thái để lưu ngay vào hệ thống',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'pending', child: Text('Chưa thực hiện')),
                    DropdownMenuItem(value: 'in_progress', child: Text('Đang thực hiện')),
                    DropdownMenuItem(value: 'completed', child: Text('Đã hoàn thành')),
                  ],
                  onChanged: (_updatingStatus || _updatingPriority || _deleting) ? null : (value) {
                    if (value != null) _changeStatus(value);
                  },
                ),
              ),
              if (_updatingStatus) const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: LinearProgressIndicator(),
              ),
              _item('Ưu tiên', _priority((_task!['priority'] ?? '').toString()), Icons.flag_outlined),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                child: DropdownButtonFormField<String>(
                  key: ValueKey('b4_priority_${_task!['priority']}'),
                  initialValue: (_task!['priority'] ?? 'medium').toString(),
                  decoration: const InputDecoration(
                    labelText: 'B4 - Thiết lập mức độ ưu tiên',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.flag_outlined),
                    helperText: 'Chọn mức ưu tiên để lưu ngay vào hệ thống',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Thấp')),
                    DropdownMenuItem(value: 'medium', child: Text('Trung bình')),
                    DropdownMenuItem(value: 'high', child: Text('Cao')),
                  ],
                  onChanged: (_updatingStatus || _updatingPriority || _deleting) ? null : (value) {
                    if (value != null) _changePriority(value);
                  },
                ),
              ),
              if (_updatingPriority) const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: LinearProgressIndicator(),
              ),
              _item('Ngày bắt đầu', _date(_task!['startDate']), Icons.today),
              _item('Hạn hoàn thành', _date(_task!['dueDate']), Icons.event),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                child: OutlinedButton.icon(
                  onPressed: (_updatingDates || _updatingStatus || _updatingPriority || _deleting) ? null : _changeDates,
                  icon: const Icon(Icons.edit_calendar_outlined),
                  label: Text(_updatingDates ? 'Đang lưu ngày...' : 'B5 - Chọn ngày bắt đầu và hạn hoàn thành'),
                ),
              ),
              _item('Thời gian tạo', _date(_task!['createdAt']), Icons.access_time),
            ])),
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: (_deleting || _updatingStatus || _updatingPriority) ? null : _edit,
              icon: const Icon(Icons.edit_outlined), label: const Text('Chỉnh sửa công việc')),
            const SizedBox(height: 10),
            OutlinedButton.icon(onPressed: (_deleting || _updatingStatus || _updatingPriority) ? null : _delete,
              icon: const Icon(Icons.delete_outline),
              label: Text(_deleting ? 'Đang xóa...' : 'Xóa công việc'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700)),
          ],
        )),
  );
}

class EditTaskScreen extends StatefulWidget {
  final Map<String, dynamic> task;
  const EditTaskScreen({super.key, required this.task});
  @override
  State<EditTaskScreen> createState() => _EditTaskScreenState();
}

class _EditTaskScreenState extends State<EditTaskScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late String _status;
  late String _priority;
  DateTime? _startDate;
  DateTime? _dueDate;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: (widget.task['title'] ?? '').toString());
    _description = TextEditingController(text: (widget.task['description'] ?? '').toString());
    _status = (widget.task['status'] ?? 'pending').toString();
    _priority = (widget.task['priority'] ?? 'medium').toString();
    _startDate = DateTime.tryParse((widget.task['startDate'] ?? '').toString());
    _dueDate = DateTime.tryParse((widget.task['dueDate'] ?? '').toString());
  }
  @override
  void dispose() { _title.dispose(); _description.dispose(); super.dispose(); }

  String _fmt(DateTime? d) => d == null ? 'Chưa đặt' :
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pick(bool start) async {
    final current = start ? _startDate : _dueDate;
    final picked = await showDatePicker(
      context: context, initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2000), lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() {
        if (start) { _startDate = picked; } else { _dueDate = picked; }
      });
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_startDate != null && _dueDate != null && _dueDate!.isBefore(_startDate!)) {
      showError(context, 'Hạn hoàn thành phải từ ngày bắt đầu trở đi.'); return;
    }
    setState(() => _busy = true);
    try {
      await Api.request('PUT', '/api/tasks/${widget.task['id']}', {
        'title': _title.text.trim(), 'description': _description.text.trim(),
        'status': _status, 'priority': _priority,
        'startDate': _startDate == null ? null : _fmt(_startDate),
        'dueDate': _dueDate == null ? null : _fmt(_dueDate),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) { if (mounted) showError(context, e); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Chỉnh sửa công việc')),
    body: SingleChildScrollView(padding: const EdgeInsets.all(18), child: Form(
      key: _form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextFormField(controller: _title, maxLength: 200,
          decoration: const InputDecoration(labelText: 'Tiêu đề *', prefixIcon: Icon(Icons.assignment_outlined)),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Vui lòng nhập tiêu đề' : null),
        const SizedBox(height: 12),
        TextFormField(controller: _description, maxLines: 3,
          decoration: const InputDecoration(labelText: 'Mô tả', prefixIcon: Icon(Icons.notes_outlined))),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(initialValue: _status,
          decoration: const InputDecoration(labelText: 'Trạng thái'),
          items: const [
            DropdownMenuItem(value: 'pending', child: Text('Chưa thực hiện')),
            DropdownMenuItem(value: 'in_progress', child: Text('Đang thực hiện')),
            DropdownMenuItem(value: 'completed', child: Text('Đã hoàn thành')),
          ], onChanged: _busy ? null : (v) { if (v != null) setState(() => _status = v); }),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(initialValue: _priority,
          decoration: const InputDecoration(labelText: 'Ưu tiên'),
          items: const [
            DropdownMenuItem(value: 'low', child: Text('Thấp')),
            DropdownMenuItem(value: 'medium', child: Text('Trung bình')),
            DropdownMenuItem(value: 'high', child: Text('Cao')),
          ], onChanged: _busy ? null : (v) { if (v != null) setState(() => _priority = v); }),
        const SizedBox(height: 14),
        OutlinedButton.icon(onPressed: _busy ? null : () => _pick(true),
          icon: const Icon(Icons.calendar_today), label: Text('Ngày bắt đầu: ${_fmt(_startDate)}')),
        OutlinedButton.icon(onPressed: _busy ? null : () => _pick(false),
          icon: const Icon(Icons.event), label: Text('Hạn hoàn thành: ${_fmt(_dueDate)}')),
        Wrap(spacing: 8, children: [
          TextButton(onPressed: _busy ? null : () => setState(() => _startDate = null), child: const Text('Bỏ ngày bắt đầu')),
          TextButton(onPressed: _busy ? null : () => setState(() => _dueDate = null), child: const Text('Bỏ hạn')),
        ]),
        const SizedBox(height: 18),
        FilledButton.icon(onPressed: _busy ? null : _save,
          icon: const Icon(Icons.save_outlined), label: Text(_busy ? 'Đang lưu...' : 'Lưu thay đổi')),
      ]),
    )),
  );
}

void showError(BuildContext context,Object error){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(error.toString().replaceFirst('Exception: ','')),backgroundColor:Colors.red.shade700));}
