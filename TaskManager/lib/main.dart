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
    Card(child:ListTile(
      leading: const Icon(Icons.list_alt_outlined),
      title: const Text('Danh sách công việc'),
      subtitle: const Text('Xem công việc do bạn tạo'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const TaskListScreen()),
      ),
    )),
    Card(child:ListTile(
      leading: const Icon(Icons.add_task_outlined),
      title: const Text('Tạo công việc mới'),
      subtitle: const Text('Tạo công việc và lưu vào hệ thống'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final created = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => const CreateTaskScreen()),
        );
        if (created == true && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã tạo công việc thành công.')),
          );
        }
      },
    )),
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
                      if (_tasks.isEmpty)
                        const Card(child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: Text('Chưa có công việc nào.')),
                        )),
                      for (final task in _tasks)
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
              _item('Ưu tiên', _priority((_task!['priority'] ?? '').toString()), Icons.flag_outlined),
              _item('Ngày bắt đầu', _date(_task!['startDate']), Icons.today),
              _item('Hạn hoàn thành', _date(_task!['dueDate']), Icons.event),
              _item('Thời gian tạo', _date(_task!['createdAt']), Icons.access_time),
            ])),
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: _deleting ? null : _edit,
              icon: const Icon(Icons.edit_outlined), label: const Text('Chỉnh sửa công việc')),
            const SizedBox(height: 10),
            OutlinedButton.icon(onPressed: _deleting ? null : _delete,
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
