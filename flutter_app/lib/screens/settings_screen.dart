import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api_service.dart';
import '../core/models.dart';
import '../core/theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _serverUrlController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _2faController = TextEditingController();

  bool _isCodeSent = false;
  bool _requires2FA = false;
  bool _isLoadingTg = false;
  String _tgStatusMsg = '';
  DedupStats? _dedupStats;

  @override
  void initState() {
    super.initState();
    final api = context.read<ApiService>();
    _serverUrlController.text = api.baseUrl;
    _loadDedup();
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    _2faController.dispose();
    super.dispose();
  }

  Future<void> _loadDedup() async {
    final api = context.read<ApiService>();
    final stats = await api.getDedupStats();
    setState(() => _dedupStats = stats);
  }

  Future<void> _saveServerUrl() async {
    final api = context.read<ApiService>();
    await api.setBaseUrl(_serverUrlController.text.trim());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('URL del servidor actualizada correctamente')),
    );
  }

  Future<void> _sendTgCode() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) return;

    setState(() {
      _isLoadingTg = true;
      _tgStatusMsg = 'Enviando código SMS/Telegram...';
    });

    final api = context.read<ApiService>();
    final res = await api.telegramSendCode(phone);

    setState(() {
      _isLoadingTg = false;
      if (res.containsKey('detail')) {
        _tgStatusMsg = res['detail'];
      } else {
        _isCodeSent = true;
        _tgStatusMsg = 'Código enviado a tu Telegram. Ingrésalo abajo.';
      }
    });
  }

  Future<void> _verifyTgCode() async {
    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();
    final password = _2faController.text.trim();

    setState(() {
      _isLoadingTg = true;
      _tgStatusMsg = 'Verificando código...';
    });

    final api = context.read<ApiService>();
    final res = await api.telegramVerifyCode(phone, code, password: password.isNotEmpty ? password : null);

    setState(() {
      _isLoadingTg = false;
      if (res.containsKey('detail') && res['detail'].toString().contains('2FA')) {
        _requires2FA = true;
        _tgStatusMsg = 'Ingresa tu contraseña 2FA (Verificación en dos pasos)';
      } else if (res.containsKey('message')) {
        _tgStatusMsg = res['message'];
        _isCodeSent = false;
        _requires2FA = false;
      } else {
        _tgStatusMsg = res['detail'] ?? 'Error de autenticación';
      }
    });
  }

  Future<void> _disconnectTg() async {
    final api = context.read<ApiService>();
    await api.telegramDisconnect();
    setState(() {
      _tgStatusMsg = 'Cuenta de Telegram desconectada.';
      _isCodeSent = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final api = context.watch<ApiService>();
    final user = api.userProfile;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User Profile Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: CyberTheme.cyberCardBox(borderColor: CyberTheme.neonCyan),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('👤 CUENTA ACTIVA', style: TextStyle(color: CyberTheme.neonCyan, fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(
                        user?.email ?? 'Sesión iniciada',
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await api.logout();
                  },
                  icon: const Icon(Icons.logout, size: 16, color: CyberTheme.neonRed),
                  label: const Text('Cerrar Sesión', style: TextStyle(color: CyberTheme.neonRed, fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: CyberTheme.neonRed),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Server URL Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: CyberTheme.cyberCardBox(borderColor: Colors.white24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🌐 SERVIDOR BACKEND EN LA NUBE', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                const Text('URL del VPS de Oracle Cloud o túnel HTTPS activo.', style: TextStyle(color: CyberTheme.textMuted, fontSize: 11)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _serverUrlController,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: 'http://127.0.0.1:8000/api/v1 o http://192.168.1.x:8000/api/v1',
                          prefixIcon: Icon(Icons.dns, color: CyberTheme.neonCyan, size: 18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: _saveServerUrl,
                      child: const Text('Guardar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Telegram Session Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: CyberTheme.cyberCardBox(borderColor: user?.telegramConnected == true ? CyberTheme.neonGreen : Colors.amber),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.send, color: CyberTheme.neonCyan, size: 24),
                        SizedBox(width: 8),
                        Text('CUENTA DE TELEGRAM', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (user?.telegramConnected == true ? CyberTheme.neonGreen : Colors.amber).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        user?.telegramConnected == true ? 'CONECTADO ⚡' : 'DESCONECTADO',
                        style: TextStyle(
                          color: user?.telegramConnected == true ? CyberTheme.neonGreen : Colors.amber,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                if (user?.telegramConnected == true) ...[
                  const Text('Tu cuenta de Telegram está vinculada con sesión Turbo MTProto activa.', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _disconnectTg,
                    icon: const Icon(Icons.link_off, size: 18, color: CyberTheme.neonRed),
                    label: const Text('Desconectar Telegram', style: TextStyle(color: CyberTheme.neonRed)),
                  ),
                ] else ...[
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Número de Teléfono (con código de país)',
                      hintText: '+5493875123456',
                      prefixIcon: Icon(Icons.phone, color: CyberTheme.neonCyan, size: 18),
                    ),
                  ),
                  const SizedBox(height: 10),

                  if (!_isCodeSent)
                    ElevatedButton.icon(
                      onPressed: _isLoadingTg ? null : _sendTgCode,
                      icon: const Icon(Icons.send, size: 18),
                      label: Text(_isLoadingTg ? 'Enviando...' : 'Enviar Código'),
                    ),

                  if (_isCodeSent) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Código de Confirmación',
                        hintText: '12345',
                        prefixIcon: Icon(Icons.password, color: CyberTheme.neonCyan, size: 18),
                      ),
                    ),
                    if (_requires2FA) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: _2faController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Contraseña 2FA',
                          prefixIcon: Icon(Icons.lock, color: CyberTheme.neonCyan, size: 18),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _isLoadingTg ? null : _verifyTgCode,
                      icon: const Icon(Icons.verified, size: 18),
                      label: Text(_isLoadingTg ? 'Verificando...' : 'Verificar y Conectar'),
                    ),
                  ],

                  if (_tgStatusMsg.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(_tgStatusMsg, style: const TextStyle(color: CyberTheme.neonCyan, fontSize: 12)),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Deduplication Savings Card
          if (_dedupStats != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: CyberTheme.cyberCardBox(borderColor: CyberTheme.neonPurple),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🔐 MOTOR DE DEDUPLICACIÓN SHA-256', style: TextStyle(color: CyberTheme.neonPurple, fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStat('Archivos Únicos', '${_dedupStats!.totalUniqueFiles}'),
                      _buildStat('Espacio Ahorrado', '${_dedupStats!.totalSavedMb} MB'),
                      _buildStat('Consultas Hasheadas', '${_dedupStats!.totalQueries}'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStat(String title, String val) {
    return Column(
      children: [
        Text(val, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        const SizedBox(height: 2),
        Text(title, style: const TextStyle(color: CyberTheme.textMuted, fontSize: 11)),
      ],
    );
  }
}
