import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api_service.dart';
import '../core/models.dart';
import '../core/theme.dart';

class QuickDownloadScreen extends StatefulWidget {
  final Function(int jobId)? onJobStarted;
  final String? initialTarget;
  const QuickDownloadScreen({super.key, this.onJobStarted, this.initialTarget});

  @override
  State<QuickDownloadScreen> createState() => _QuickDownloadScreenState();
}

class _QuickDownloadScreenState extends State<QuickDownloadScreen> {
  final TextEditingController _urlController = TextEditingController();
  double _concurrency = 10;
  String _destination = 'DIRECT_DOWNLOAD';
  String _mediaFilter = 'ALL';
  bool _isAnalyzingTopics = false;
  List<TopicModel> _topics = [];
  bool _isStarting = false;
  int _linkCount = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialTarget != null && widget.initialTarget!.isNotEmpty) {
      _urlController.text = widget.initialTarget!;
      _updateLinkCount(widget.initialTarget!);
    }
    _urlController.addListener(() {
      _updateLinkCount(_urlController.text);
    });
  }

  void _updateLinkCount(String text) {
    if (text.trim().isEmpty) {
      if (_linkCount != 0) setState(() => _linkCount = 0);
      return;
    }
    final tokens = text.split(RegExp(r'[\r\n,;]+')).map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
    if (_linkCount != tokens.length) {
      setState(() => _linkCount = tokens.length);
    }
  }

  @override
  void didUpdateWidget(covariant QuickDownloadScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTarget != null && widget.initialTarget != oldWidget.initialTarget) {
      _urlController.text = widget.initialTarget!;
      _updateLinkCount(widget.initialTarget!);
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _analyzeTopics() async {
    final target = _urlController.text.trim();
    if (target.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ingresa el enlace del canal o grupo con topics.')),
        );
      }
      return;
    }

    setState(() {
      _isAnalyzingTopics = true;
    });

    final api = context.read<ApiService>();
    final data = await api.preAnalyzeTopics(target, concurrency: _concurrency.toInt());

    if (mounted) {
      setState(() {
        _isAnalyzingTopics = false;
        if (data.containsKey('topics')) {
          _topics = (data['topics'] as List).map((t) => TopicModel.fromJson(t)).toList();
        } else {
          _topics = [];
        }
      });
    }
  }

  Future<void> _startDownload() async {
    final target = _urlController.text.trim();
    if (target.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Por favor ingresa un enlace de Telegram.')),
        );
      }
      return;
    }

    setState(() {
      _isStarting = true;
    });

    final api = context.read<ApiService>();

    List<int>? selectedTopicIds;
    String jobType = 'SINGLE_LINK';

    if (_topics.isNotEmpty && _topics.any((t) => t.isSelected)) {
      selectedTopicIds = _topics.where((t) => t.isSelected).map((t) => t.id).toList();
      jobType = 'FORUM_TOPICS';
    } else if (_linkCount > 1 || target.contains('\n') || target.contains(',') || target.contains(';')) {
      jobType = 'BATCH_LINKS';
    } else {
      final clean = target.split('?')[0].trim();
      final isSingleMsg = RegExp(r't\.me/(?:c/)?[\w-]+/\d+(?:/\d+)?$').hasMatch(clean);
      if (isSingleMsg) {
        jobType = 'SINGLE_LINK';
      } else {
        jobType = 'BATCH_CHANNEL';
      }
    }

    final jobId = await api.createJob(
      targetUrl: target,
      jobType: jobType,
      concurrency: _concurrency.toInt(),
      destination: _destination,
      filterMedia: _mediaFilter == 'ALL' ? null : _mediaFilter,
      topicIds: selectedTopicIds,
    );

    if (mounted) {
      setState(() {
        _isStarting = false;
      });

      if (jobId != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tarea #$jobId iniciada exitosamente ($jobType)')),
        );
        if (widget.onJobStarted != null) {
          widget.onJobStarted!(jobId);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al iniciar la tarea en el servidor.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: CyberTheme.cyberCardBox(borderColor: CyberTheme.neonGreen),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.bolt, color: CyberTheme.neonGreen, size: 28),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'TURBO DESCARGAS & EXTRACTOR DE TOPICS',
                        style: TextStyle(
                          color: CyberTheme.neonGreen,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Descarga 1 o múltiples enlaces (10, 20, 50+), canales o foros enteros a máxima velocidad.',
                  style: TextStyle(color: CyberTheme.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 16),

                if (_linkCount > 1) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: CyberTheme.neonCyan.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: CyberTheme.neonCyan.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.playlist_add_check, color: CyberTheme.neonCyan, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          '🔗 $_linkCount enlaces detectados (Modo Lote Multi-Link)',
                          style: const TextStyle(
                            color: CyberTheme.neonCyan,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                TextField(
                  controller: _urlController,
                  minLines: 3,
                  maxLines: 7,
                  style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    labelText: 'Enlace(s) de Telegram (1 o varios, 1 por línea)',
                    hintText: 'https://t.me/c/12345/678\nhttps://t.me/c/12345/679\nhttps://t.me/canal/123',
                    prefixIcon: Icon(Icons.link, color: CyberTheme.neonCyan, size: 20),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 14),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Conexiones Paralelas Turbo:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    Text(
                      '${_concurrency.toInt()} hilos concurrentes ⚡',
                      style: const TextStyle(color: CyberTheme.neonYellow, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                    ),
                  ],
                ),
                Slider(
                  value: _concurrency,
                  min: 1,
                  max: 20,
                  divisions: 19,
                  activeColor: CyberTheme.neonCyan,
                  inactiveColor: Colors.white12,
                  onChanged: (val) => setState(() => _concurrency = val),
                ),
                const SizedBox(height: 10),

                Wrap(
                  spacing: 16,
                  runSpacing: 10,
                  children: [
                    DropdownButton<String>(
                      value: _destination,
                      dropdownColor: const Color(0xFF0A0F1D),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      items: const [
                        DropdownMenuItem(value: 'DIRECT_DOWNLOAD', child: Text('📥 Descarga Directa / ZIP')),
                        DropdownMenuItem(value: 'GOOGLE_DRIVE', child: Text('☁️ Google Drive Desktop')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _destination = val);
                      },
                    ),

                    DropdownButton<String>(
                      value: _mediaFilter,
                      dropdownColor: const Color(0xFF0A0F1D),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      items: const [
                        DropdownMenuItem(value: 'ALL', child: Text('Todos los Medios')),
                        DropdownMenuItem(value: 'VIDEO', child: Text('Solo Videos')),
                        DropdownMenuItem(value: 'PHOTO', child: Text('Solo Fotos')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _mediaFilter = val);
                      },
                    ),

                    OutlinedButton.icon(
                      onPressed: _isAnalyzingTopics ? null : _analyzeTopics,
                      icon: _isAnalyzingTopics
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: CyberTheme.neonCyan))
                          : const Icon(Icons.account_tree, size: 18),
                      label: Text(_isAnalyzingTopics ? 'Analizando...' : 'Escanear Topics'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isStarting ? null : _startDownload,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: _isStarting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: CyberTheme.neonGreen))
                        : const Icon(Icons.rocket_launch, size: 22),
                    label: Text(
                      _isStarting ? 'INICIANDO TAREA TURBO...' : 'INICIAR EXTRACCIÓN TURBO ⚡',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (_topics.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: CyberTheme.cyberCardBox(borderColor: Colors.blueAccent),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'TEMAS / TOPICS DETECTADOS ()',
                        style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => setState(() {
                              for (var t in _topics) {
                                t.isSelected = true;
                              }
                            }),
                            child: const Text('Marcar Todos', style: TextStyle(color: CyberTheme.neonCyan, fontSize: 12)),
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              for (var t in _topics) {
                                t.isSelected = false;
                              }
                            }),
                            child: const Text('Desmarcar', style: TextStyle(color: Colors.white54, fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _topics.length,
                    separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (context, idx) {
                      final t = _topics[idx];
                      return CheckboxListTile(
                        value: t.isSelected,
                        activeColor: Colors.blueAccent,
                        title: Text(t.title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: Text('ID:  • Disponibles: ', style: const TextStyle(color: CyberTheme.textMuted, fontSize: 11)),
                        onChanged: (val) {
                          setState(() {
                            t.isSelected = val ?? false;
                          });
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
