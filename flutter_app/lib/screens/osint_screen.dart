import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/api_service.dart';
import '../core/models.dart';
import '../core/theme.dart';

class OsintScreen extends StatefulWidget {
  final Function(String target)? onSelectTarget;
  const OsintScreen({super.key, this.onSelectTarget});

  @override
  State<OsintScreen> createState() => _OsintScreenState();
}

class _OsintScreenState extends State<OsintScreen> {
  final TextEditingController _targetController = TextEditingController();
  List<ChatModel> _chats = [];
  bool _isLoadingChats = false;
  bool _isInspecting = false;

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  @override
  void dispose() {
    _targetController.dispose();
    super.dispose();
  }

  Future<void> _loadChats() async {
    setState(() => _isLoadingChats = true);
    final api = context.read<ApiService>();
    final list = await api.getMyChats();
    if (mounted) {
      setState(() {
        _chats = list;
        _isLoadingChats = false;
      });
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: CyberTheme.bgCard,
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: CyberTheme.neonGreen, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('$label copiado al portapapeles: $text', style: const TextStyle(color: Colors.white, fontSize: 12))),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _inspect(String target, {String? chatTitle, bool isForum = false}) async {
    setState(() {
      _targetController.text = target;
      _isInspecting = true;
    });

    final api = context.read<ApiService>();
    final res = await api.inspectChat(target);

    if (mounted) {
      setState(() {
        _isInspecting = false;
      });

      _showInspectionModal(target, chatTitle ?? res['title'] ?? 'Canal / Grupo', res, isForum: isForum);
    }
  }

  void _showInspectionModal(String target, String title, Map<String, dynamic> data, {bool isForum = false}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: CyberTheme.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: Colors.tealAccent, width: 1.5),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          bool isAnalyzingTopics = false;
          List<TopicModel> loadedTopics = [];

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.65,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            builder: (_, scrollCtrl) => SingleChildScrollView(
              controller: scrollCtrl,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(isForum ? Icons.forum : Icons.radar, color: Colors.tealAccent, size: 26),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'ID: $target • ${data['type'] ?? (isForum ? "Foro de Topics" : "Canal")}',
                              style: const TextStyle(color: CyberTheme.textMuted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Metadata chips
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      _buildChip('Total Mensajes', '${data['total_messages'] ?? "-"}'),
                      _buildChip('Fotos', '${data['photos'] ?? "-"}'),
                      _buildChip('Videos', '${data['videos'] ?? "-"}'),
                      _buildChip('Documentos', '${data['documents'] ?? "-"}'),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: CyberTheme.neonCyan,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.download, size: 18),
                          label: const Text('DESCARGAR AHORA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          onPressed: () {
                            Navigator.pop(ctx);
                            if (widget.onSelectTarget != null) {
                              widget.onSelectTarget!(target);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                        ),
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('Copiar ID', style: TextStyle(fontSize: 12)),
                        onPressed: () => _copyToClipboard(target, 'ID'),
                      ),
                    ],
                  ),

                  if (isForum || (data['type'] ?? '').toString().toLowerCase().contains('foro')) ...[
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent.withValues(alpha: 0.15),
                        foregroundColor: Colors.blueAccent,
                        side: const BorderSide(color: Colors.blueAccent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: isAnalyzingTopics
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent))
                          : const Icon(Icons.folder_open, size: 18),
                      label: Text(isAnalyzingTopics ? 'Cargando Topics...' : '📂 EXPLORAR TOPICS Y TEMAS'),
                      onPressed: isAnalyzingTopics
                          ? null
                          : () async {
                              setModalState(() => isAnalyzingTopics = true);
                              final api = context.read<ApiService>();
                              final topData = await api.preAnalyzeTopics(target);
                              setModalState(() {
                                isAnalyzingTopics = false;
                                if (topData.containsKey('topics')) {
                                  loadedTopics = (topData['topics'] as List).map((t) => TopicModel.fromJson(t)).toList();
                                }
                              });
                            },
                    ),

                    if (loadedTopics.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        'Temas detectados (${loadedTopics.length}):',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: loadedTopics.length,
                        itemBuilder: (context, tIdx) {
                          final t = loadedTopics[tIdx];
                          return CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            activeColor: Colors.blueAccent,
                            title: Text(t.title, style: const TextStyle(color: Colors.white, fontSize: 12)),
                            subtitle: Text('Archivos aprox: ${t.totalFiles} • ${t.sizeMb}', style: const TextStyle(color: CyberTheme.textMuted, fontSize: 10)),
                            value: t.isSelected,
                            onChanged: (val) {
                              setModalState(() => t.isSelected = val ?? false);
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.download_for_offline, size: 18),
                        label: const Text('Descargar Topics Seleccionados', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          if (widget.onSelectTarget != null) {
                            widget.onSelectTarget!(target);
                          }
                        },
                      ),
                    ],
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: CyberTheme.cyberCardBox(borderColor: Colors.tealAccent),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.radar, color: Colors.tealAccent, size: 28),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'CENTRO DE INTELIGENCIA OSINT & CANALES',
                        style: TextStyle(
                          color: Colors.tealAccent,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Inspección de metadatos, volumen de medios y descarga directa de canales, grupos y topics.',
                  style: TextStyle(color: CyberTheme.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 14),

                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _targetController,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: 'Ingresa link o ID (ej: -100..., @canal, https://t.me/...)',
                          prefixIcon: Icon(Icons.search, color: Colors.tealAccent, size: 18),
                        ),
                        onSubmitted: (val) => _inspect(val.trim()),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: _isInspecting ? null : () => _inspect(_targetController.text.trim()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.tealAccent.withValues(alpha: 0.15),
                        foregroundColor: Colors.tealAccent,
                        side: const BorderSide(color: Colors.tealAccent),
                      ),
                      icon: _isInspecting
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.tealAccent))
                          : const Icon(Icons.biotech, size: 18),
                      label: Text(_isInspecting ? 'Analizando...' : 'INSPECCIONAR'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // My Chats List
          Container(
            padding: const EdgeInsets.all(16),
            decoration: CyberTheme.cyberCardBox(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('TUS GRUPOS Y CANALES DE TELEGRAM', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: CyberTheme.neonCyan, size: 18),
                      onPressed: _loadChats,
                      tooltip: 'Actualizar lista',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_isLoadingChats)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator(color: CyberTheme.neonCyan)),
                  )
                else if (_chats.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('No se encontraron chats o no hay cuenta de Telegram vinculada.', style: TextStyle(color: CyberTheme.textMuted, fontSize: 12))),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _chats.length,
                    separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (context, idx) {
                      final c = _chats[idx];
                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: (c.isForum ? Colors.blueAccent : (c.isChannel ? CyberTheme.neonCyan : Colors.tealAccent)).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: (c.isForum ? Colors.blueAccent : (c.isChannel ? CyberTheme.neonCyan : Colors.tealAccent)).withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Icon(
                                    c.isForum ? Icons.forum : (c.isChannel ? Icons.campaign : Icons.group),
                                    color: c.isForum ? Colors.blueAccent : (c.isChannel ? CyberTheme.neonCyan : Colors.tealAccent),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        c.title,
                                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Text(
                                            'ID: ${c.id}',
                                            style: const TextStyle(color: CyberTheme.textMuted, fontSize: 11, fontFamily: 'monospace'),
                                          ),
                                          if (c.isForum) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: Colors.blueAccent.withValues(alpha: 0.2),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text('TOPICS', style: TextStyle(color: Colors.blueAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Action Buttons Row
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                InkWell(
                                  onTap: () => _copyToClipboard('${c.id}', 'ID'),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.white12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(Icons.copy, size: 12, color: Colors.white70),
                                        SizedBox(width: 4),
                                        Text('Copiar ID', style: TextStyle(color: Colors.white70, fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                ),
                                InkWell(
                                  onTap: () => _inspect('${c.id}', chatTitle: c.title, isForum: c.isForum),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: Colors.tealAccent.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.4)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(Icons.radar, size: 12, color: Colors.tealAccent),
                                        SizedBox(width: 4),
                                        Text('Inspeccionar', style: TextStyle(color: Colors.tealAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                ),
                                InkWell(
                                  onTap: () {
                                    if (widget.onSelectTarget != null) {
                                      widget.onSelectTarget!('${c.id}');
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: CyberTheme.neonCyan.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: CyberTheme.neonCyan.withValues(alpha: 0.4)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(Icons.download, size: 12, color: CyberTheme.neonCyan),
                                        SizedBox(width: 4),
                                        Text('Descargar ➔', style: TextStyle(color: CyberTheme.neonCyan, fontSize: 11, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String label, String val) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white12),
      ),
      child: Text('$label: $val', style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace')),
    );
  }
}
