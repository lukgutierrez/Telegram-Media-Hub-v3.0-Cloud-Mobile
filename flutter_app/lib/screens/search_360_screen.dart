import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/api_service.dart';
import '../core/models.dart';
import '../core/theme.dart';

class Search360Screen extends StatefulWidget {
  final Function(int jobId)? onJobStarted;
  const Search360Screen({super.key, this.onJobStarted});

  @override
  State<Search360Screen> createState() => _Search360ScreenState();
}

class _Search360ScreenState extends State<Search360Screen> {
  final TextEditingController _queryController = TextEditingController();
  String _selectedFilter = 'ALL';
  bool _isSearching = false;
  List<SearchResult> _results = [];
  SearchSummary? _summary;
  bool _selectAll = true;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor ingresa un término de búsqueda (ej: GOROSO, Maca Escudero, etc.).')),
      );
      return;
    }

    setState(() {
      _isSearching = true;
    });

    final api = context.read<ApiService>();
    final data = await api.searchTelegramGlobal(query, filter: _selectedFilter, limit: 150);

    setState(() {
      _results = data['results'] as List<SearchResult>;
      _summary = data['summary'] as SearchSummary;
      _isSearching = false;
      _selectAll = true;
    });
  }

  Future<void> _downloadSingle(SearchResult r) async {
    final api = context.read<ApiService>();
    final url = api.getSingleMediaDownloadUrl(r.chatId, r.msgId);
    final uri = Uri.parse(url);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Descargando ${r.filename} en tu dispositivo... ⬇️')),
      );
    }
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      debugPrint('Error launching single media URL: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al abrir enlace: $e')),
        );
      }
    }
  }

  Future<void> _downloadBatchZip({bool onlySelected = true}) async {
    final items = onlySelected
        ? _results.where((r) => r.hasMedia && r.isSelected).toList()
        : _results.where((r) => r.hasMedia).toList();

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay archivos multimedia seleccionados para descargar.')),
      );
      return;
    }

    final api = context.read<ApiService>();
    final query = _queryController.text.trim().isNotEmpty ? _queryController.text.trim() : 'Busqueda';
    final jobId = await api.startSearchBatchJob(query, items, concurrency: 10);

    if (jobId != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tarea #$jobId iniciada! Descargando y empaquetando en ZIP...')),
      );
      if (widget.onJobStarted != null) {
        widget.onJobStarted!(jobId);
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al iniciar la descarga en el servidor.')),
      );
    }
  }

  Widget _buildOriginBadge(String origin) {
    Color bg;
    Color border;
    Color text;
    String label;

    switch (origin) {
      case 'FORUM_TOPIC':
        bg = Colors.blue.withValues(alpha: 0.15);
        border = Colors.blue.withValues(alpha: 0.4);
        text = Colors.blueAccent;
        label = 'TOPIC';
        break;
      case 'ALBUM_PACK':
        bg = CyberTheme.neonPurple.withValues(alpha: 0.15);
        border = CyberTheme.neonPurple.withValues(alpha: 0.4);
        text = const Color(0xFFD8B4FE);
        label = 'ÁLBUM';
        break;
      case 'CONTEXT_ADJACENT':
        bg = Colors.amber.withValues(alpha: 0.15);
        border = Colors.amber.withValues(alpha: 0.4);
        text = Colors.amberAccent;
        label = 'MENCIÓN';
        break;
      default:
        bg = CyberTheme.neonCyan.withValues(alpha: 0.1);
        border = CyberTheme.neonCyan.withValues(alpha: 0.3);
        text = CyberTheme.neonCyan;
        label = 'DIRECTO';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(color: text, fontSize: 9, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
      ),
    );
  }

  Widget _buildMediaTypeBadge(String type) {
    Color bg;
    Color text;
    IconData icon;
    String label;

    switch (type) {
      case 'VIDEO':
        bg = CyberTheme.neonGreen.withValues(alpha: 0.15);
        text = CyberTheme.neonGreen;
        icon = Icons.videocam;
        label = 'Video';
        break;
      case 'PHOTO':
        bg = CyberTheme.neonCyan.withValues(alpha: 0.15);
        text = CyberTheme.neonCyan;
        icon = Icons.photo;
        label = 'Foto';
        break;
      case 'DOCUMENT':
        bg = CyberTheme.neonYellow.withValues(alpha: 0.15);
        text = CyberTheme.neonYellow;
        icon = Icons.insert_drive_file;
        label = 'Doc';
        break;
      default:
        bg = Colors.white10;
        text = Colors.white70;
        icon = Icons.text_snippet;
        label = 'Texto';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: text),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: text, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ],
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
            decoration: CyberTheme.cyberCardBox(borderColor: CyberTheme.neonCyan),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.saved_search, color: CyberTheme.neonCyan, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'BÚSQUEDA ULTRA PROFUNDA 360° EN TELEGRAM',
                            style: TextStyle(
                              color: CyberTheme.neonCyan,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.1,
                            ),
                          ),
                          Text(
                            'Rastreo multicapa en vivo: Foros (Topics), Packs de Álbumes y Menciones Adyacentes con empaquetado ZIP.',
                            style: TextStyle(color: CyberTheme.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Search inputs
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 280,
                      child: TextField(
                        controller: _queryController,
                        style: const TextStyle(fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: 'Término (ej: GOROSO, Maca...)',
                          prefixIcon: Icon(Icons.search, color: CyberTheme.neonCyan, size: 18),
                        ),
                        onSubmitted: (_) => _performSearch(),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B132B),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: CyberTheme.borderCyan.withValues(alpha: 0.3)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedFilter,
                          dropdownColor: const Color(0xFF0A0F1D),
                          style: const TextStyle(color: CyberTheme.textLight, fontSize: 13),
                          items: const [
                            DropdownMenuItem(value: 'ALL', child: Text('Todos los Tipos')),
                            DropdownMenuItem(value: 'MEDIA_ONLY', child: Text('Solo Multimedia')),
                            DropdownMenuItem(value: 'VIDEO', child: Text('Solo Videos')),
                            DropdownMenuItem(value: 'PHOTO', child: Text('Solo Fotos')),
                            DropdownMenuItem(value: 'DOCUMENT', child: Text('Solo Documentos')),
                          ],
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedFilter = val);
                          },
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _isSearching ? null : _performSearch,
                      icon: _isSearching
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: CyberTheme.neonGreen))
                          : const Icon(Icons.bolt, size: 18),
                      label: Text(_isSearching ? 'ESCANEA TELEGRAM...' : 'BUSCAR 360°'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Summary Stats Box
          if (_summary != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: CyberTheme.cyberCardBox(borderColor: CyberTheme.neonGreen),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem('Coincidencias', '', CyberTheme.neonCyan),
                      _buildStatItem('Videos', '', CyberTheme.neonGreen),
                      _buildStatItem('Fotos', '', Colors.lightBlueAccent),
                      _buildStatItem('Peso Total', ' MB', CyberTheme.neonYellow),
                    ],
                  ),
                  const Divider(color: Colors.white12, height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _downloadBatchZip(onlySelected: false),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: CyberTheme.neonGreen.withValues(alpha: 0.2),
                          foregroundColor: CyberTheme.neonGreen,
                          side: const BorderSide(color: CyberTheme.neonGreen, width: 1.5),
                        ),
                        icon: const Icon(Icons.folder_zip, size: 20),
                        label: const Text('DESCARGAR TODO EN ZIP ORGANIZADO 📦'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _downloadBatchZip(onlySelected: true),
                        icon: const Icon(Icons.check_box, size: 18),
                        label: const Text('Descargar Seleccionados en ZIP'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Results List
          if (_results.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Checkbox(
                      value: _selectAll,
                      activeColor: CyberTheme.neonCyan,
                      onChanged: (val) {
                        setState(() {
                          _selectAll = val ?? false;
                          for (var r in _results) {
                            if (r.hasMedia) r.isSelected = _selectAll;
                          }
                        });
                      },
                    ),
                    const Text('Seleccionar Todos los Medios', style: TextStyle(color: CyberTheme.textMuted, fontSize: 12)),
                  ],
                ),
                Text(' resultados', style: const TextStyle(color: CyberTheme.textMuted, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),

            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _results.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final r = _results[index];
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: CyberTheme.cyberCardBox(bgColor: const Color(0xFF090D1A)),
                  child: Row(
                    children: [
                      if (r.hasMedia)
                        Checkbox(
                          value: r.isSelected,
                          activeColor: CyberTheme.neonCyan,
                          onChanged: (val) {
                            setState(() {
                              r.isSelected = val ?? false;
                            });
                          },
                        )
                      else
                        const SizedBox(width: 32, child: Center(child: Text('-', style: TextStyle(color: Colors.white24)))),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '📁 ',
                                    style: const TextStyle(color: CyberTheme.neonCyan, fontSize: 13, fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                _buildOriginBadge(r.origin),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              r.text.isNotEmpty ? r.text : '[Multimedia]',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                _buildMediaTypeBadge(r.mediaType),
                                if (r.sizeMb > 0)
                                  Text(
                                    ' MB',
                                    style: const TextStyle(color: CyberTheme.neonYellow, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                                  ),
                                Text(
                                  '👤  • ',
                                  style: const TextStyle(color: CyberTheme.textMuted, fontSize: 10),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (r.hasMedia)
                        IconButton(
                          icon: const Icon(Icons.download, color: CyberTheme.neonCyan),
                          tooltip: 'Descargar archivo individual',
                          onPressed: () => _downloadSingle(r),
                        ),
                    ],
                  ),
                );
              },
            ),
          ] else if (!_isSearching && _summary != null) ...[
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              child: const Text(
                'No se encontraron mensajes o archivos con ese término.',
                style: TextStyle(color: CyberTheme.textMuted, fontSize: 14),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatItem(String title, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        const SizedBox(height: 2),
        Text(title, style: const TextStyle(color: CyberTheme.textMuted, fontSize: 11)),
      ],
    );
  }
}
