import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api_service.dart';
import '../core/theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _serverController = TextEditingController();

  bool _isLoginMode = true;
  bool _isLoading = false;
  bool _showServerConfig = false;
  String _errorMsg = '';
  String _successMsg = '';

  @override
  void initState() {
    super.initState();
    final api = context.read<ApiService>();
    _serverController.text = api.baseUrl;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final serverUrl = _serverController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _errorMsg = 'Por favor ingresa tu correo y contraseña.';
        _successMsg = '';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMsg = '';
      _successMsg = '';
    });

    final api = context.read<ApiService>();
    if (serverUrl.isNotEmpty && serverUrl != api.baseUrl) {
      await api.setBaseUrl(serverUrl);
    }

    bool success = false;
    if (_isLoginMode) {
      success = await api.login(email, password);
      if (!success && mounted) {
        setState(() => _errorMsg = 'Correo o contraseña incorrectos. Revisa tus datos.');
      }
    } else {
      success = await api.register(email, password);
      if (!success && mounted) {
        setState(() => _errorMsg = 'No se pudo crear la cuenta. Verifica si el correo ya existe.');
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _showForgotPasswordDialog() {
    final emailCtrl = TextEditingController(text: _emailController.text.trim());
    final newPassCtrl = TextEditingController();
    String dialogMsg = '';
    bool isResetting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: CyberTheme.bgCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: CyberTheme.neonCyan, width: 1.5),
          ),
          title: Row(
            children: const [
              Icon(Icons.lock_reset, color: CyberTheme.neonCyan, size: 24),
              SizedBox(width: 8),
              Text(
                'RECUPERAR CONTRASEÑA',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ingresa tu correo y la nueva contraseña que deseas asignar:',
                  style: TextStyle(color: CyberTheme.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Correo Electrónico',
                    prefixIcon: Icon(Icons.email_outlined, color: CyberTheme.neonCyan, size: 18),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newPassCtrl,
                  obscureText: true,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Nueva Contraseña',
                    prefixIcon: Icon(Icons.key, color: CyberTheme.neonGreen, size: 18),
                  ),
                ),
                if (dialogMsg.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    dialogMsg,
                    style: TextStyle(
                      color: dialogMsg.contains('éxito') ? CyberTheme.neonGreen : CyberTheme.neonRed,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: isResetting
                  ? null
                  : () async {
                      final em = emailCtrl.text.trim();
                      final np = newPassCtrl.text.trim();
                      if (em.isEmpty || np.isEmpty) {
                        setDialogState(() => dialogMsg = 'Completa todos los campos.');
                        return;
                      }
                      if (np.length < 6) {
                        setDialogState(() => dialogMsg = 'La contraseña debe tener al menos 6 caracteres.');
                        return;
                      }
                      setDialogState(() => isResetting = true);
                      final api = context.read<ApiService>();
                      final ok = await api.resetPassword(em, np);
                      setDialogState(() => isResetting = false);
                      if (ok) {
                        setDialogState(() => dialogMsg = '¡Contraseña cambiada con éxito!');
                        await Future.delayed(const Duration(seconds: 1));
                        if (mounted) {
                          Navigator.pop(ctx);
                          setState(() {
                            _emailController.text = em;
                            _passwordController.text = np;
                            _successMsg = 'Contraseña restablecida con éxito. Puedes ingresar.';
                          });
                        }
                      } else {
                        setDialogState(() => dialogMsg = 'No se encontró una cuenta con ese correo.');
                      }
                    },
              child: Text(isResetting ? 'Guardando...' : 'Restablecer'),
            ),
          ],
        ),
      ),
    );
  }

  void _showQuickCodeDialog() {
    final codeCtrl = TextEditingController();
    String dialogMsg = '';
    bool isAuthenticating = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: CyberTheme.bgCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: CyberTheme.neonGreen, width: 1.5),
          ),
          title: Row(
            children: const [
              Icon(Icons.qr_code_scanner, color: CyberTheme.neonGreen, size: 24),
              SizedBox(width: 8),
              Text(
                'VINCULAR POR CÓDIGO QR / PIN',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'En tu computadora haz clic en "Vincular Celular" e introduce el código PIN de 6 caracteres que aparece en pantalla:',
                  style: TextStyle(color: CyberTheme.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: codeCtrl,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3,
                    fontFamily: 'monospace',
                    color: CyberTheme.neonGreen,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'CÓDIGO PIN',
                    hintText: 'TMH-1234',
                    prefixIcon: Icon(Icons.key, color: CyberTheme.neonGreen, size: 20),
                  ),
                ),
                if (dialogMsg.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    dialogMsg,
                    style: TextStyle(
                      color: dialogMsg.contains('éxito') ? CyberTheme.neonGreen : CyberTheme.neonRed,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: CyberTheme.neonGreen,
                foregroundColor: Colors.black,
              ),
              onPressed: isAuthenticating
                  ? null
                  : () async {
                      final code = codeCtrl.text.trim();
                      if (code.isEmpty) {
                        setDialogState(() => dialogMsg = 'Ingresa el código PIN.');
                        return;
                      }
                      setDialogState(() {
                        isAuthenticating = true;
                        dialogMsg = '';
                      });
                      final api = context.read<ApiService>();
                      final ok = await api.loginWithQuickCode(code);
                      setDialogState(() => isAuthenticating = false);
                      if (ok) {
                        setDialogState(() => dialogMsg = '¡Vinculación exitosa!');
                        await Future.delayed(const Duration(milliseconds: 600));
                        if (mounted) {
                          Navigator.pop(ctx);
                        }
                      } else {
                        setDialogState(() => dialogMsg = 'Código inválido o expirado. Genera uno nuevo en la web.');
                      }
                    },
              child: Text(isAuthenticating ? 'Validando...' : 'Vincular y Entrar ➔'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CyberTheme.bgDark,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo & Brand Header
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: CyberTheme.neonCyan.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: CyberTheme.neonCyan, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: CyberTheme.neonCyan.withValues(alpha: 0.35),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.bolt, color: CyberTheme.neonCyan, size: 46),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'TELEGRAM MEDIA HUB 360°',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Motor Turbo MTProto • Sincronización en la Nube',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: CyberTheme.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 26),

                  // Auth Card
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: CyberTheme.cyberCardBox(
                      borderColor: _isLoginMode ? CyberTheme.neonCyan : CyberTheme.neonGreen,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Tabs Login / Registro
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() {
                                  _isLoginMode = true;
                                  _errorMsg = '';
                                  _successMsg = '';
                                }),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: _isLoginMode ? CyberTheme.neonCyan : Colors.transparent,
                                        width: 2.5,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    'INICIAR SESIÓN',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: _isLoginMode ? CyberTheme.neonCyan : Colors.white54,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() {
                                  _isLoginMode = false;
                                  _errorMsg = '';
                                  _successMsg = '';
                                }),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: !_isLoginMode ? CyberTheme.neonGreen : Colors.transparent,
                                        width: 2.5,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    'CREAR CUENTA',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: !_isLoginMode ? CyberTheme.neonGreen : Colors.white54,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Email
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(fontSize: 14),
                          decoration: const InputDecoration(
                            labelText: 'Correo Electrónico',
                            hintText: 'tu@correo.com',
                            prefixIcon: Icon(Icons.email_outlined, color: CyberTheme.neonCyan, size: 20),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Password
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          style: const TextStyle(fontSize: 14),
                          decoration: const InputDecoration(
                            labelText: 'Contraseña',
                            prefixIcon: Icon(Icons.lock_outline, color: CyberTheme.neonCyan, size: 20),
                          ),
                        ),

                        // Olvidé mi contraseña button
                        if (_isLoginMode) ...[
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _showForgotPasswordDialog,
                              child: const Text(
                                '¿Olvidaste tu contraseña?',
                                style: TextStyle(color: CyberTheme.neonCyan, fontSize: 11, decoration: TextDecoration.underline),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),

                        // Messages
                        if (_errorMsg.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: CyberTheme.neonRed.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: CyberTheme.neonRed.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, color: CyberTheme.neonRed, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(_errorMsg, style: const TextStyle(color: CyberTheme.neonRed, fontSize: 12)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],

                        if (_successMsg.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: CyberTheme.neonGreen.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: CyberTheme.neonGreen.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle_outline, color: CyberTheme.neonGreen, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(_successMsg, style: const TextStyle(color: CyberTheme.neonGreen, fontSize: 12)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],

                        // Submit Button
                        ElevatedButton(
                          onPressed: _isLoading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isLoginMode ? CyberTheme.neonCyan : CyberTheme.neonGreen,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                )
                              : Text(
                                  _isLoginMode ? 'ACCEDER AL SISTEMA ➔' : 'REGISTRARME Y ENTRAR ➔',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1),
                                ),
                        ),
                        
                        // Quick PIN / QR Login Action
                        if (_isLoginMode) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _showQuickCodeDialog,
                            icon: const Icon(Icons.qr_code_scanner, color: CyberTheme.neonGreen, size: 18),
                            label: const Text(
                              '⚡ VINCULAR CON QR / CÓDIGO PIN',
                              style: TextStyle(
                                color: CyberTheme.neonGreen,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: CyberTheme.neonGreen, width: 1.2),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              backgroundColor: CyberTheme.neonGreen.withValues(alpha: 0.08),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),

                        // Configuración Avanzada de Servidor Toggle
                        InkWell(
                          onTap: () => setState(() => _showServerConfig = !_showServerConfig),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _showServerConfig ? Icons.expand_less : Icons.expand_more,
                                color: CyberTheme.textMuted,
                                size: 18,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _showServerConfig ? 'Ocultar servidor' : '⚙️ Servidor en la Nube (VPS)',
                                style: const TextStyle(color: CyberTheme.textMuted, fontSize: 11),
                              ),
                            ],
                          ),
                        ),

                        if (_showServerConfig) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _serverController,
                            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                            decoration: const InputDecoration(
                              labelText: 'URL del Servidor Backend',
                              hintText: 'https://pdas-stats-orbit-forbes.trycloudflare.com/api/v1',
                              prefixIcon: Icon(Icons.cloud_outlined, color: CyberTheme.neonPurple, size: 18),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  const Text(
                    'Desarrollado por @lukgtz • Salta, Argentina',
                    style: TextStyle(color: CyberTheme.textMuted, fontSize: 11, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
