import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ModerationReportsScreen extends StatefulWidget {
  const ModerationReportsScreen({super.key});

  @override
  State<ModerationReportsScreen> createState() =>
      _ModerationReportsScreenState();
}

class _ModerationReportsScreenState
    extends State<ModerationReportsScreen> {
  final supabase = Supabase.instance.client;

  bool isLoading = true;
  bool isModerator = false;

  String selectedStatus = 'all';

  List<Map<String, dynamic>> reports = [];

  @override
  void initState() {
    super.initState();
    loadReports();
  }

  Future<void> loadReports() async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
    });

    try {
      final moderatorResult =
          await supabase.rpc('is_moderator');

      isModerator = moderatorResult == true;

      if (!isModerator) {
        if (mounted) {
          setState(() {
            reports = [];
            isLoading = false;
          });
        }
        return;
      }

      final result = await supabase.rpc(
        'get_moderation_reports',
        params: {
          'p_status':
              selectedStatus == 'all' ? null : selectedStatus,
          'p_limit': 100,
        },
      );

      final data = (result as List)
          .map(
            (item) => Map<String, dynamic>.from(item as Map),
          )
          .toList();

      if (!mounted) return;

      setState(() {
        reports = data;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to load moderation reports: $e',
          ),
        ),
      );
    }
  }

  Future<void> updateReportStatus(
    Map<String, dynamic> report,
  ) async {
    final reportId = report['id']?.toString();

    if (reportId == null || reportId.isEmpty) {
      return;
    }

    String selected = report['status']?.toString() ?? 'pending';
    final notesController = TextEditingController(
      text: report['moderator_notes']?.toString() ?? '',
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Update Report'),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selected,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'pending',
                          child: Text('Pending'),
                        ),
                        DropdownMenuItem(
                          value: 'reviewing',
                          child: Text('Reviewing'),
                        ),
                        DropdownMenuItem(
                          value: 'resolved',
                          child: Text('Resolved'),
                        ),
                        DropdownMenuItem(
                          value: 'rejected',
                          child: Text('Rejected'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;

                        setDialogState(() {
                          selected = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: notesController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Moderator notes',
                        hintText: 'Optional internal notes...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result != true) {
      notesController.dispose();
      return;
    }

    try {
      await supabase.rpc(
        'update_report_status',
        params: {
          'p_report_id': reportId,
          'p_status': selected,
          'p_moderator_notes':
              notesController.text.trim().isEmpty
                  ? null
                  : notesController.text.trim(),
        },
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report updated successfully.'),
        ),
      );

      await loadReports();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to update report: $e',
          ),
        ),
      );
    } finally {
      notesController.dispose();
    }
  }

  Future<void> showReportDetails(
    Map<String, dynamic> report,
  ) async {
    final reason =
        report['reason']?.toString() ?? 'No reason';
    final details =
        report['details']?.toString() ?? '';
    final status =
        report['status']?.toString() ?? 'pending';
    final reporterId =
        report['reporter_id']?.toString() ?? '-';
    final reportedUserId =
        report['reported_user_id']?.toString() ?? '-';
    final createdAt =
        report['created_at']?.toString() ?? '-';
    final reviewedAt =
        report['reviewed_at']?.toString() ?? '';
    final notes =
        report['moderator_notes']?.toString() ?? '';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Report Details'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailRow('Status', status),
                const SizedBox(height: 8),
                _detailRow('Reason', reason),
                const SizedBox(height: 8),
                _detailRow(
                  'Reporter',
                  reporterId,
                ),
                const SizedBox(height: 8),
                _detailRow(
                  'Reported user',
                  reportedUserId,
                ),
                const SizedBox(height: 8),
                _detailRow(
                  'Created',
                  createdAt,
                ),
                if (reviewedAt.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _detailRow(
                    'Reviewed',
                    reviewedAt,
                  ),
                ],
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Details',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(details),
                ],
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Moderator notes',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(notes),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                updateReportStatus(report);
              },
              child: const Text('Update'),
            ),
          ],
        );
      },
    );
  }

  Widget _detailRow(
    String label,
    String value,
  ) {
    return RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'reviewing':
        return Colors.blue;
      case 'resolved':
        return Colors.green;
      case 'rejected':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  Widget _statusChip(String status) {
    final color = _statusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildReportCard(
    Map<String, dynamic> report,
  ) {
    final reason =
        report['reason']?.toString() ?? 'Unknown reason';
    final status =
        report['status']?.toString() ?? 'pending';
    final details =
        report['details']?.toString() ?? '';
    final createdAt =
        report['created_at']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showReportDetails(report),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      reason,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _statusChip(status),
                ],
              ),
              if (details.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  details,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.access_time,
                    size: 15,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      createdAt,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.color,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        updateReportStatus(report),
                    icon: const Icon(
                      Icons.edit_outlined,
                      size: 18,
                    ),
                    label: const Text('Update'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Moderation Reports'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!isModerator) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Moderation Reports'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 56,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Access denied',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Only moderators and administrators can access moderation reports.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: loadReports,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Moderation Reports'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: loadReports,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 58,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              children: [
                _filterChip('all', 'All'),
                _filterChip('pending', 'Pending'),
                _filterChip('reviewing', 'Reviewing'),
                _filterChip('resolved', 'Resolved'),
                _filterChip('rejected', 'Rejected'),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: loadReports,
              child: reports.isEmpty
                  ? ListView(
                      physics:
                          const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        Center(
                          child: Text(
                            'No reports found.',
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics:
                          const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        12,
                        4,
                        12,
                        24,
                      ),
                      itemCount: reports.length,
                      itemBuilder: (context, index) {
                        return _buildReportCard(
                          reports[index],
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(
    String value,
    String label,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selectedStatus == value,
        onSelected: (selected) {
          if (!selected) return;

          setState(() {
            selectedStatus = value;
          });

          loadReports();
        },
      ),
    );
  }
}
