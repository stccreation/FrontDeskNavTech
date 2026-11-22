import 'package:flutter/material.dart';

import 'api_client.dart';
import 'ticket_ui.dart';
import 'frontdesk_design.dart';

String _isoDate(DateTime day) => day.toIso8601String().split('T').first;

class HolidayEntry {
  HolidayEntry.fromJson(Map<String, dynamic> data)
    : date = DateTime.parse(data['date'] as String),
      name = data['name'] as String;

  final DateTime date;
  final String name;
}

class HolidaySchedule {
  HolidaySchedule.fromJson(Map<String, dynamic> data)
    : today = DateTime.parse(data['today'] as String),
      holidays = (data['holidays'] as List<dynamic>)
          .map((item) => HolidayEntry.fromJson(item as Map<String, dynamic>))
          .toList();

  final DateTime today;
  final List<HolidayEntry> holidays;
}

class HolidayApi {
  HolidayApi(this._client);

  final ApiClient _client;

  Future<HolidaySchedule> list() async =>
      HolidaySchedule.fromJson(await _client.get('/api/holidays'));

  Future<int> add(DateTime date, String name) async {
    final result = await _client.post('/api/holidays', {
      'date': _isoDate(date),
      'name': name,
    });
    return result['deadlines_updated'] as int;
  }

  Future<int> remove(DateTime date) async {
    final result = await _client.post(
      '/api/holidays/${_isoDate(date)}/remove',
      {},
    );
    return result['deadlines_updated'] as int;
  }
}

class HolidayCalendarPage extends StatefulWidget {
  const HolidayCalendarPage({super.key, required this.api});

  final HolidayApi api;

  @override
  State<HolidayCalendarPage> createState() => _HolidayCalendarPageState();
}

class _HolidayCalendarPageState extends State<HolidayCalendarPage> {
  HolidaySchedule? _schedule;
  String? _error;
  bool _loading = true;
  bool _removing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final schedule = await widget.api.list();
      if (mounted) setState(() => _schedule = schedule);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSaved(int changed) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          changed == 0
              ? 'Holiday calendar updated.'
              : 'Updated $changed SLA deadline${changed == 1 ? '' : 's'}.',
        ),
      ),
    );
  }

  Future<void> _add(DateTime today) async {
    final changed = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _NewHolidayDialog(api: widget.api, today: today),
    );
    if (!mounted || changed == null) return;
    _showSaved(changed);
    await _load();
  }

  Future<void> _remove(HolidayEntry holiday) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove holiday?'),
        content: Text(
          '${holiday.name} will be removed from the calendar for future working time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove holiday'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _removing = true;
      _error = null;
    });
    try {
      final changed = await widget.api.remove(holiday.date);
      if (!mounted) return;
      _showSaved(changed);
      await _load();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final schedule = _schedule;
    final error = _error;
    final busy = _loading || _removing;
    final locale = MaterialLocalizations.of(context);
    return Scaffold(
      backgroundColor: ticketPageColor,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              children: [
                DeskPageHeading(
                  'Holiday calendar',
                  description:
                      'Working hours are Monday to Friday, 9:30 AM–6:30 PM IST. Holidays pause working time.',
                  actions: [
                    IconButton(
                      tooltip: 'Refresh holidays',
                      onPressed: busy ? null : _load,
                      icon: const Icon(Icons.refresh),
                    ),
                    FilledButton.icon(
                      onPressed: busy || schedule == null
                          ? null
                          : () => _add(schedule.today),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add holiday'),
                    ),
                  ],
                ),
                if (error != null) TicketErrorText(error),
                const SizedBox(height: 22),
                if (schedule == null && _loading)
                  const Center(
                    child: CircularProgressIndicator(
                      semanticsLabel: 'Loading holidays',
                    ),
                  ),
                if (schedule != null) ...[
                  if (schedule.holidays.isEmpty)
                    const DeskEmptyState(
                      icon: Icons.event_available_outlined,
                      title: 'No holidays scheduled',
                    ),
                  for (final holiday in schedule.holidays)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: Colors.white,
                      child: ListTile(
                        leading: Container(
                          width: 46,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8EFE2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            holiday.date.day.toString().padLeft(2, '0'),
                            style: const TextStyle(
                              color: deskGreen,
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                        ),
                        title: Text(
                          holiday.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        subtitle: Text(locale.formatFullDate(holiday.date)),
                        trailing: holiday.date.isBefore(schedule.today)
                            ? const Text('Past')
                            : TextButton(
                                onPressed: busy ? null : () => _remove(holiday),
                                child: const Text('Remove'),
                              ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NewHolidayDialog extends StatefulWidget {
  const _NewHolidayDialog({required this.api, required this.today});

  final HolidayApi api;
  final DateTime today;

  @override
  State<_NewHolidayDialog> createState() => _NewHolidayDialogState();
}

class _NewHolidayDialogState extends State<_NewHolidayDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  late final _date = TextEditingController(text: _isoDate(widget.today));
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _date.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final last = DateTime(widget.today.year + 30, 12, 31);
    final entered = DateTime.tryParse(_date.text);
    final initial =
        entered != null &&
            !entered.isBefore(widget.today) &&
            !entered.isAfter(last)
        ? entered
        : widget.today;
    final date = await showDatePicker(
      context: context,
      firstDate: widget.today,
      lastDate: last,
      initialDate: initial,
    );
    if (mounted && date != null) _date.text = _isoDate(date);
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final changed = await widget.api.add(
        DateTime.parse(_date.text.trim()),
        _name.text,
      );
      if (mounted) Navigator.pop(context, changed);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: const Text('Add holiday'),
        scrollable: true,
        content: SizedBox(
          width: 430,
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _date,
                  enabled: !_saving,
                  decoration: InputDecoration(
                    labelText: 'Date',
                    helperText: 'YYYY-MM-DD',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      onPressed: _saving ? null : _pickDate,
                      tooltip: 'Choose date',
                      icon: const Icon(Icons.calendar_today_outlined),
                    ),
                  ),
                  validator: (value) {
                    final text = value!.trim();
                    final day = DateTime.tryParse(text);
                    if (day == null || _isoDate(day) != text) {
                      return 'Enter a date in YYYY-MM-DD format.';
                    }
                    if (day.isBefore(widget.today)) {
                      return 'Choose today or a future date.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  enabled: !_saving,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Holiday name',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                  validator: (value) =>
                      value!.trim().isEmpty ? 'Enter a holiday name.' : null,
                ),
                if (error != null) TicketErrorText(error),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save holiday'),
          ),
        ],
      ),
    );
  }
}
