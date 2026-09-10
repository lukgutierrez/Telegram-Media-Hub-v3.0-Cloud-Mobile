import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/api_service.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../core/websocket_service.dart';

class JobsScreen extends StatefulWidget {
  final int? initialJobId;
  const JobsScreen({super.key, this.initialJobId});

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  int? _activeJobId;
  List<JobModel> _jobs = [];
  List<JobFileModel> _activeJobFiles = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _activeJobId = widget.initialJobId;
    _refreshJobs();
  }

  @override
  void didUpdateWidget(covariant JobsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialJobId != null && widget.initialJobId != oldWidget.initialJobId) {
      _activeJobId = widget.initialJobId;
      _refreshJobs();
    }
  }

  Future<void> _refreshJobs() async {
    setState(() => _isLoading = true);
    final api = context.read<ApiService>();
    final jobs = await api.getJobs();
    setState(() {
      _jobs = jobs;
      if (_activeJobId == null && _jobs.isNotEmpty) {
        _activeJobId = _jobs.first.id;
      }
      _isLoading = false;
    });

    if (_activeJobId != null) {
      _loadJobFiles(_activeJobId!);
    }
  }

  Future<void> _loadJobFiles(int jobId) async {
    setState(() => _activeJobId = jobId);
    final api = context.read<ApiService>();
    final files = await api.getJobFiles(jobId);
    setState(() {
      _activeJobFiles = files;
    });
  }

  Future<void> _sendSignal(String action) async {
    if (_activeJobId == null) return;
    final api = context.read<ApiService>();
    final ok = await api.sendJobSignal(_activeJobId!, action);
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Señal "$action" enviada a la tarea #$_activeJobId')),
      );
    }
  }

  Future<void> _downloadJobZip(int jobId) async {
    final api = context.read<ApiService>();
    final url = api.getZipDownloadUrl(jobId);
    final uri = Uri.parse(url);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Iniciando descarga del paquete ZIP en tu navegador... 📦')),
      );
    }
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      debugPrint('Error launching zip URL: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al abrir enlace: $e')),
        );
      }
    }
  }

  Future<void> _downloadFile(JobFileModel file) async {
    final api = context.read<ApiService>();
    if (file.downloadUrl != null) {
      final fullUrl = file.downloadUrl!.startsWith('http')
          ? file.downloadUrl!
          : '${api.rootServerUrl}${file.downloadUrl}?token=${api.token}';
      final uri = Uri.parse(fullUrl);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Descargando ${file.filename}... ⬇️')),
        );
      }
      try {
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!launched) {
          await launchUrl(uri, mode: LaunchMode.platformDefault);
        }
      } catch (e) {
        debugPrint('Error launching file URL: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al abrir enlace: $e')),
          );
        }
      }
    }
  }

  String _formatEta(int seconds) {
    if (seconds <= 0) return 'Listo / En Curso';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')} min';
  }

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WebSocketService>();
    final live = ws.latestProgress;

    final isLiveForActive = live != null && live.jobId == _activeJobId;
    final progressVal = isLiveForActive ? live.progress : 0.0;
    final speedVal = isLiveForActive ? live.speedMbs : 0.0;
    final etaVal = isLiveForActive ? live.etaSeconds : 0;
    final statusVal = isLiveForActive ? live.status : 'EN ESPERA';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isLoading) const LinearProgressIndicator(color: CyberTheme.neonGreen, backgroundColor: CyberTheme.bgCard),
          const SizedBox(height: 8),
          // Live Telemetry Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: CyberTheme.cyberCardBox(borderColor: CyberTheme.neonCyan),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.speed, color: CyberTheme.neonCyan, size: 24),
                        const SizedBox(width: 8),
                        Text(
                          'TELEMETRÍA EN TIEMPO REAL ${_activeJobId != null ? "(#$_activeJobId)" : ""}',
                          style: const TextStyle(color: CyberTheme.neonCyan, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: CyberTheme.neonGreen.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: CyberTheme.neonGreen.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        statusVal,
                        style: const TextStyle(color: CyberTheme.neonGreen, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildMetric('Velocidad', '${speedVal.toStringAsFixed(1)} MB/s', CyberTheme.neonYellow),
                    _buildMetric('Progreso', '${(progressVal * 100).toInt()}%', CyberTheme.neonGreen),
                    _buildMetric('ETA Estimado', _formatEta(etaVal), Colors.cyanAccent),
                    _buildMetric('Dedup ⚡', '${live?.dedupCount ?? 0}', CyberTheme.neonPurple),
                  ],
                ),
                const SizedBox(height: 14),

                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progressVal > 0 ? progressVal : null,
                    minHeight: 10,
                    backgroundColor: Colors.white10,
                    valueColor: const AlwaysStoppedAnimation<Color>(CyberTheme.neonGreen),
                  ),
                ),
                const SizedBox(height: 14),

                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _sendSignal('pause'),
                      icon: const Icon(Icons.pause, size: 16, color: Colors.amberAccent),
                      label: const Text('Pausar', style: TextStyle(color: Colors.amberAccent, fontSize: 12)),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendSignal('resume'),
                      icon: const Icon(Icons.play_arrow, size: 16, color: CyberTheme.neonGreen),
                      label: const Text('Reanudar', style: TextStyle(color: CyberTheme.neonGreen, fontSize: 12)),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendSignal('cancel'),
                      icon: const Icon(Icons.stop, size: 16, color: CyberTheme.neonRed),
                      label: const Text('Cancelar', style: TextStyle(color: CyberTheme.neonRed, fontSize: 12)),
                    ),
                    if (_activeJobId != null)
                      ElevatedButton.icon(
                        onPressed: () => _downloadJobZip(_activeJobId!),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: CyberTheme.neonGreen.withValues(alpha: 0.2),
                          foregroundColor: CyberTheme.neonGreen,
                          side: const BorderSide(color: CyberTheme.neonGreen),
                        ),
                        icon: const Icon(Icons.folder_zip, size: 18),
                        label: const Text('Descargar Todo en ZIP 📦', style: TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Job Files & Job History
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > 750) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: _buildFilesBox()),
                    const SizedBox(width: 14),
                    Expanded(flex: 2, child: _buildHistoryBox()),
                  ],
                );
              } else {
                return Column(
                  children: [
                    _buildFilesBox(),
                    const SizedBox(height: 14),
                    _buildHistoryBox(),
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilesBox() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: CyberTheme.cyberCardBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ARCHIVOS DE LA TAREA ${_activeJobId != null ? "#$_activeJobId" : ""}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18, color: CyberTheme.neonCyan),
                onPressed: () {
                  if (_activeJobId != null) _loadJobFiles(_activeJobId!);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_activeJobFiles.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('No hay archivos registrados para esta tarea aún.', style: TextStyle(color: CyberTheme.textMuted, fontSize: 12)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _activeJobFiles.length,
              separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
              itemBuilder: (context, idx) {
                final f = _activeJobFiles[idx];
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.insert_drive_file, color: CyberTheme.neonCyan, size: 20),
                  title: Text(f.filename, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                  subtitle: Text('${f.sizeMb} MB • SHA256: ${f.sha256.isNotEmpty ? f.sha256.substring(0, 8) : "-"}...', style: const TextStyle(color: CyberTheme.textMuted, fontSize: 10, fontFamily: 'monospace')),
                  trailing: f.hasLocalDownload
                      ? IconButton(
                          icon: const Icon(Icons.download, color: CyberTheme.neonCyan, size: 18),
                          onPressed: () => _downloadFile(f),
                        )
                      : null,
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryBox() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: CyberTheme.cyberCardBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'HISTORIAL DE TAREAS',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18, color: CyberTheme.neonCyan),
                onPressed: _refreshJobs,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_jobs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('No hay tareas registradas.', style: TextStyle(color: CyberTheme.textMuted, fontSize: 12)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _jobs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, idx) {
                final j = _jobs[idx];
                final isSelected = j.id == _activeJobId;
                return InkWell(
                  onTap: () => _loadJobFiles(j.id),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isSelected ? CyberTheme.neonCyan.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected ? CyberTheme.neonCyan : Colors.white12,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('#${j.id} ${j.jobType}', style: const TextStyle(color: CyberTheme.neonCyan, fontSize: 11, fontWeight: FontWeight.bold)),
                            Text(j.status, style: TextStyle(color: j.status == 'COMPLETED' ? CyberTheme.neonGreen : Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(j.targetUrl, style: const TextStyle(color: Colors.white70, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text('Archivos: ${j.processedFiles}/${j.totalFiles}', style: const TextStyle(color: CyberTheme.textMuted, fontSize: 10)),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildMetric(String title, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        const SizedBox(height: 2),
        Text(title, style: const TextStyle(color: CyberTheme.textMuted, fontSize: 11)),
      ],
    );
  }
}
