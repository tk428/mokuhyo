import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MokuhyoApp());
}

const Color kBg = Color(0xFFF4F6F8);
const Color kText = Color(0xFF172033);
const Color kMuted = Color(0xFF64748B);
const Color kBlue = Color(0xFF4FC3F7);
const Color kBlueSoft = Color(0xFFEAF8FF);
const Color kYellow = Color(0xFFFFF3C4);
const Color kGreen = Color(0xFFEAFaf0);
const Color kGray = Color(0xFFEEF2F7);

const List<String> kAutoStamps = ['🐌', '🫠', '🌧️', '😴', '🍵'];

String dateKey(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

DateTime parseDateKey(String key) {
  final p = key.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

DateTime businessToday() {
  final now = DateTime.now().subtract(const Duration(hours: 3));
  return DateTime(now.year, now.month, now.day);
}

String businessTodayKey() => dateKey(businessToday());

String monthTitle(DateTime d) => '${d.year}年${d.month}月';

String randomAutoStamp(String seed) {
  final index = seed.codeUnits.fold<int>(0, (a, b) => a + b) % kAutoStamps.length;
  return kAutoStamps[index];
}

enum RecordStatus {
  main,
  sub,
  miss,
  auto,
}

String statusLabel(RecordStatus s) {
  switch (s) {
    case RecordStatus.main:
      return '本目標達成';
    case RecordStatus.sub:
      return 'サブ目標達成';
    case RecordStatus.miss:
      return '未達成';
    case RecordStatus.auto:
      return '未記録';
  }
}

String statusEmoji(RecordStatus s, {String? autoStamp}) {
  switch (s) {
    case RecordStatus.main:
      return '🌟';
    case RecordStatus.sub:
      return '✅';
    case RecordStatus.miss:
      return '☁️';
    case RecordStatus.auto:
      return autoStamp ?? '🐌';
  }
}

RecordStatus statusFromString(String s) {
  return RecordStatus.values.firstWhere(
    (e) => e.name == s,
    orElse: () => RecordStatus.auto,
  );
}

class Goal {
  Goal({
    required this.id,
    required this.name,
    required this.mainTarget,
    required this.subTarget,
    required this.createdDateKey,
    this.notificationTime = '21:00',
    this.isActive = true,
  });

  final String id;
  String name;
  String mainTarget;
  String subTarget;
  String createdDateKey;
  String notificationTime;
  bool isActive;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mainTarget': mainTarget,
        'subTarget': subTarget,
        'createdDateKey': createdDateKey,
        'notificationTime': notificationTime,
        'isActive': isActive,
      };

  factory Goal.fromJson(Map<String, dynamic> json) {
    return Goal(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      mainTarget: json['mainTarget'] as String? ?? '',
      subTarget: json['subTarget'] as String? ?? '',
      createdDateKey: json['createdDateKey'] as String? ?? businessTodayKey(),
      notificationTime: json['notificationTime'] as String? ?? '21:00',
      isActive: json['isActive'] as bool? ?? true,
    );
  }
}

class GoalRecord {
  GoalRecord({
    required this.goalId,
    required this.dateKey,
    required this.status,
    this.memo = '',
    this.autoStamp,
  });

  final String goalId;
  final String dateKey;
  RecordStatus status;
  String memo;
  String? autoStamp;

  String get key => '$goalId|$dateKey';

  Map<String, dynamic> toJson() => {
        'goalId': goalId,
        'dateKey': dateKey,
        'status': status.name,
        'memo': memo,
        'autoStamp': autoStamp,
      };

  factory GoalRecord.fromJson(Map<String, dynamic> json) {
    return GoalRecord(
      goalId: json['goalId'] as String,
      dateKey: json['dateKey'] as String,
      status: statusFromString(json['status'] as String? ?? 'auto'),
      memo: json['memo'] as String? ?? '',
      autoStamp: json['autoStamp'] as String?,
    );
  }
}

class AppState extends ChangeNotifier {
  static const _goalsKey = 'mokuhyo_goals_v1';
  static const _recordsKey = 'mokuhyo_records_v1';

  final List<Goal> goals = [];
  final Map<String, GoalRecord> records = {};

  bool loaded = false;

  List<Goal> get activeGoals => goals.where((g) => g.isActive).toList();
  List<Goal> get stoppedGoals => goals.where((g) => !g.isActive).toList();

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    final goalsRaw = prefs.getString(_goalsKey);
    final recordsRaw = prefs.getString(_recordsKey);

    goals.clear();
    records.clear();

    if (goalsRaw != null && goalsRaw.isNotEmpty) {
      final list = jsonDecode(goalsRaw) as List<dynamic>;
      goals.addAll(list.map((e) => Goal.fromJson(e as Map<String, dynamic>)));
    }

    if (recordsRaw != null && recordsRaw.isNotEmpty) {
      final list = jsonDecode(recordsRaw) as List<dynamic>;
      for (final e in list) {
        final record = GoalRecord.fromJson(e as Map<String, dynamic>);
        records[record.key] = record;
      }
    }

    _autoFillUnrecordedDays();
    loaded = true;
    await save();
    notifyListeners();
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();

    final goalsJson = jsonEncode(goals.map((g) => g.toJson()).toList());
    final recordsJson = jsonEncode(records.values.map((r) => r.toJson()).toList());

    await prefs.setString(_goalsKey, goalsJson);
    await prefs.setString(_recordsKey, recordsJson);
  }

  void _autoFillUnrecordedDays() {
    final today = businessToday();

    for (final goal in goals.where((g) => g.isActive)) {
      DateTime d = parseDateKey(goal.createdDateKey);

      while (d.isBefore(today)) {
        final key = '${goal.id}|${dateKey(d)}';

        if (!records.containsKey(key)) {
          final stamp = randomAutoStamp(key);
          records[key] = GoalRecord(
            goalId: goal.id,
            dateKey: dateKey(d),
            status: RecordStatus.auto,
            autoStamp: stamp,
          );
        }

        d = d.add(const Duration(days: 1));
      }
    }
  }

  GoalRecord? recordFor(String goalId, String dayKey) {
    return records['$goalId|$dayKey'];
  }

  Future<void> upsertRecord({
    required String goalId,
    required String dayKey,
    required RecordStatus status,
    String memo = '',
    String? autoStamp,
  }) async {
    records['$goalId|$dayKey'] = GoalRecord(
      goalId: goalId,
      dateKey: dayKey,
      status: status,
      memo: memo,
      autoStamp: autoStamp,
    );
    notifyListeners();
    await save();
  }

  Future<void> addGoal({
    required String name,
    required String mainTarget,
    required String subTarget,
    required String notificationTime,
  }) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    goals.add(
      Goal(
        id: id,
        name: name,
        mainTarget: mainTarget,
        subTarget: subTarget,
        notificationTime: notificationTime,
        createdDateKey: businessTodayKey(),
      ),
    );
    notifyListeners();
    await save();
  }

  Future<void> updateGoal(Goal goal) async {
    notifyListeners();
    await save();
  }

  Future<void> stopGoal(Goal goal) async {
    goal.isActive = false;
    notifyListeners();
    await save();
  }

  Future<void> resumeGoal(Goal goal) async {
    goal.isActive = true;
    notifyListeners();
    await save();
  }

  int countMainLast30(Goal goal) {
    return _last30Records(goal).where((r) => r?.status == RecordStatus.main).length;
  }

  int countSubLast30(Goal goal) {
    return _last30Records(goal).where((r) => r?.status == RecordStatus.sub).length;
  }

  int countAutoLast30(Goal goal) {
    return _last30Records(goal).where((r) => r?.status == RecordStatus.auto).length;
  }

  int countMissLast30(Goal goal) {
    return _last30Records(goal).where((r) => r?.status == RecordStatus.miss).length;
  }

  double mainPercentLast30(Goal goal) {
    return countMainLast30(goal) / 30;
  }

  int streak(Goal goal) {
    int count = 0;
    DateTime d = businessToday();

    while (true) {
      final r = recordFor(goal.id, dateKey(d));
      if (r == null) break;

      if (r.status == RecordStatus.main || r.status == RecordStatus.sub) {
        count++;
        d = d.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }

    return count;
  }

  List<GoalRecord?> _last30Records(Goal goal) {
    final result = <GoalRecord?>[];
    DateTime d = businessToday();

    for (int i = 0; i < 30; i++) {
      result.add(recordFor(goal.id, dateKey(d)));
      d = d.subtract(const Duration(days: 1));
    }

    return result;
  }
}

class MokuhyoApp extends StatefulWidget {
  const MokuhyoApp({super.key});

  @override
  State<MokuhyoApp> createState() => _MokuhyoAppState();
}

class _MokuhyoAppState extends State<MokuhyoApp> {
  final AppState appState = AppState();

  @override
  void initState() {
    super.initState();
    appState.load();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'できたシール',
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: kBlue),
            scaffoldBackgroundColor: kBg,
            fontFamily: 'sans',
          ),
          home: appState.loaded
              ? RootPage(appState: appState)
              : const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                ),
        );
      },
    );
  }
}

class RootPage extends StatefulWidget {
  const RootPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      TodayPage(appState: widget.appState),
      CalendarPage(appState: widget.appState),
      GoalsPage(appState: widget.appState),
    ];

    return Scaffold(
      body: SafeArea(child: pages[index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        backgroundColor: Colors.white.withOpacity(0.94),
        indicatorColor: kBlueSoft,
        destinations: const [
          NavigationDestination(icon: Text('🏠', style: TextStyle(fontSize: 22)), label: '今日'),
          NavigationDestination(icon: Text('🗓', style: TextStyle(fontSize: 22)), label: 'カレンダー'),
          NavigationDestination(icon: Text('🎯', style: TextStyle(fontSize: 22)), label: '目標'),
        ],
      ),
    );
  }
}

class TodayPage extends StatelessWidget {
  const TodayPage({super.key, required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final todayKey = businessTodayKey();
    final goals = appState.activeGoals;

    final unrecorded = goals.where((g) => appState.recordFor(g.id, todayKey) == null).toList();
    final recorded = goals.where((g) => appState.recordFor(g.id, todayKey) != null).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('午前3:00切り替え', style: TextStyle(color: kMuted, fontWeight: FontWeight.w800)),
                  SizedBox(height: 4),
                  Text(
                    '今日の記録',
                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -1.6),
                  ),
                ],
              ),
            ),
            RoundIconButton(
              icon: '+',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => GoalEditPage(appState: appState)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SummaryCard(
          title: 'まだ記録していない目標',
          big: '${unrecorded.length}',
          suffix: '個',
          caption: '下のカードから、本目標・サブ目標・未達を選ぶ',
        ),
        const SizedBox(height: 22),
        SectionTitle(
          title: '未達成・未記録',
          right: '今日まだ押していない目標',
        ),
        if (goals.isEmpty)
          EmptyPanel(
            title: 'まだ目標がありません',
            text: 'まずは1つ目標を作ろう。\n例：筋トレ、本目標30分、サブ目標1分。',
            buttonText: '＋ 目標を作る',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => GoalEditPage(appState: appState)),
            ),
          )
        else if (unrecorded.isEmpty)
          const EmptyPanel(
            title: '今日の未記録はありません',
            text: '全部記録済み。いい感じ。',
          )
        else
          ...unrecorded.map(
            (g) => TodayGoalCard(
              goal: g,
              appState: appState,
              dateKey: todayKey,
            ),
          ),
        const SizedBox(height: 20),
        SectionTitle(
          title: '記録済み',
          right: '押し直しで変更可能',
        ),
        if (recorded.isEmpty)
          const EmptyPanel(
            title: 'まだ記録済みはありません',
            text: '本目標・サブ・未達を押すとここへ移動します。',
          )
        else
          ...recorded.map(
            (g) => RecordedGoalCard(
              goal: g,
              record: appState.recordFor(g.id, todayKey)!,
              appState: appState,
            ),
          ),
      ],
    );
  }
}

class TodayGoalCard extends StatelessWidget {
  const TodayGoalCard({
    super.key,
    required this.goal,
    required this.appState,
    required this.dateKey,
  });

  final Goal goal;
  final AppState appState;
  final String dateKey;

  @override
  Widget build(BuildContext context) {
    return BaseGoalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GoalCardHeader(
            name: goal.name,
            badge: '未記録',
          ),
          const SizedBox(height: 14),
          TargetBox(label: '本目標', text: goal.mainTarget, color: kYellow),
          const SizedBox(height: 8),
          TargetBox(label: 'サブ目標', text: goal.subTarget, color: kGreen),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: StampButton(
                  emoji: '🌟',
                  label: '本目標',
                  color: kYellow,
                  onTap: () => openMemoSheet(
                    context: context,
                    title: '本目標達成！',
                    emoji: '🌟',
                    onSave: (memo) => appState.upsertRecord(
                      goalId: goal.id,
                      dayKey: dateKey,
                      status: RecordStatus.main,
                      memo: memo,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StampButton(
                  emoji: '✅',
                  label: 'サブ',
                  color: kGreen,
                  onTap: () => openMemoSheet(
                    context: context,
                    title: 'サブ目標達成！',
                    emoji: '✅',
                    onSave: (memo) => appState.upsertRecord(
                      goalId: goal.id,
                      dayKey: dateKey,
                      status: RecordStatus.sub,
                      memo: memo,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StampButton(
                  emoji: '☁️',
                  label: '未達',
                  color: kGray,
                  onTap: () => openMemoSheet(
                    context: context,
                    title: '未達成として記録',
                    emoji: '☁️',
                    onSave: (memo) => appState.upsertRecord(
                      goalId: goal.id,
                      dayKey: dateKey,
                      status: RecordStatus.miss,
                      memo: memo,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class RecordedGoalCard extends StatelessWidget {
  const RecordedGoalCard({
    super.key,
    required this.goal,
    required this.record,
    required this.appState,
  });

  final Goal goal;
  final GoalRecord record;
  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final emoji = statusEmoji(record.status, autoStamp: record.autoStamp);

    return BaseGoalCard(
      borderColor: const Color(0xFFC7F0D8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GoalCardHeader(
            name: goal.name,
            badge: '$emoji ${statusLabel(record.status)}',
          ),
          const SizedBox(height: 10),
          if (record.memo.isNotEmpty)
            Text(
              record.memo,
              style: const TextStyle(fontWeight: FontWeight.w800, color: kMuted),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: '変更する',
                  onTap: () => openRecordEditSheet(
                    context: context,
                    appState: appState,
                    goal: goal,
                    dayKey: record.dateKey,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  String? selectedGoalId;
  DateTime visibleMonth = DateTime(businessToday().year, businessToday().month);

  @override
  Widget build(BuildContext context) {
    final goals = widget.appState.goals;
    final activeOrFirst = goals.isEmpty ? null : goals.firstWhere(
      (g) => g.id == selectedGoalId,
      orElse: () => goals.first,
    );

    selectedGoalId ??= activeOrFirst?.id;

    final selectedGoal = activeOrFirst;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        const Text('スタンプ帳', style: TextStyle(color: kMuted, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text(
          'カレンダー',
          style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -1.6),
        ),
        const SizedBox(height: 16),
        if (goals.isEmpty)
          const EmptyPanel(
            title: '表示する目標がありません',
            text: '目標を作ると、ここにカレンダーが表示されます。',
          )
        else ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: goals.map((g) {
                final active = g.id == selectedGoalId;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(g.name),
                    selected: active,
                    onSelected: (_) => setState(() => selectedGoalId = g.id),
                    selectedColor: kText,
                    labelStyle: TextStyle(
                      color: active ? Colors.white : kMuted,
                      fontWeight: FontWeight.w900,
                    ),
                    backgroundColor: Colors.white,
                    side: BorderSide.none,
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          if (selectedGoal != null) CalendarSummary(appState: widget.appState, goal: selectedGoal),
          const SizedBox(height: 16),
          CalendarCard(
            appState: widget.appState,
            goal: selectedGoal!,
            visibleMonth: visibleMonth,
            onPrev: () => setState(() {
              visibleMonth = DateTime(visibleMonth.year, visibleMonth.month - 1);
            }),
            onNext: () => setState(() {
              visibleMonth = DateTime(visibleMonth.year, visibleMonth.month + 1);
            }),
          ),
        ],
      ],
    );
  }
}

class CalendarSummary extends StatelessWidget {
  const CalendarSummary({
    super.key,
    required this.appState,
    required this.goal,
  });

  final AppState appState;
  final Goal goal;

  @override
  Widget build(BuildContext context) {
    return BaseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(goal.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(
            '本目標：${goal.mainTarget} / サブ：${goal.subTarget}',
            style: const TextStyle(color: kMuted, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: StatTile(emoji: '🌟', number: '${appState.countMainLast30(goal)}', label: '本目標')),
              const SizedBox(width: 8),
              Expanded(child: StatTile(emoji: '✅', number: '${appState.countSubLast30(goal)}', label: 'サブ')),
              const SizedBox(width: 8),
              Expanded(child: StatTile(emoji: '🐌', number: '${appState.countAutoLast30(goal)}', label: '未記録')),
              const SizedBox(width: 8),
              Expanded(child: StatTile(emoji: '☁️', number: '${appState.countMissLast30(goal)}', label: '未達')),
            ],
          ),
        ],
      ),
    );
  }
}

class CalendarCard extends StatelessWidget {
  const CalendarCard({
    super.key,
    required this.appState,
    required this.goal,
    required this.visibleMonth,
    required this.onPrev,
    required this.onNext,
  });

  final AppState appState;
  final Goal goal;
  final DateTime visibleMonth;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(visibleMonth.year, visibleMonth.month, 1);
    final daysInMonth = DateTime(visibleMonth.year, visibleMonth.month + 1, 0).day;
    final startOffset = first.weekday % 7;
    final totalCells = startOffset + daysInMonth;
    final rows = (totalCells / 7).ceil();
    final cellCount = rows * 7;

    return BaseCard(
      child: Column(
        children: [
          Row(
            children: [
              IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left)),
              Expanded(
                child: Center(
                  child: Text(
                    monthTitle(visibleMonth),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
            ],
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              Expanded(child: Dow('日')),
              Expanded(child: Dow('月')),
              Expanded(child: Dow('火')),
              Expanded(child: Dow('水')),
              Expanded(child: Dow('木')),
              Expanded(child: Dow('金')),
              Expanded(child: Dow('土')),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            itemCount: cellCount,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 7,
              mainAxisSpacing: 7,
            ),
            itemBuilder: (context, index) {
              final dayNumber = index - startOffset + 1;

              if (dayNumber < 1 || dayNumber > daysInMonth) {
                return const SizedBox();
              }

              final d = DateTime(visibleMonth.year, visibleMonth.month, dayNumber);
              final key = dateKey(d);
              final record = appState.recordFor(goal.id, key);
              final emoji = record == null
                  ? '・'
                  : statusEmoji(record.status, autoStamp: record.autoStamp);

              final isToday = key == businessTodayKey();

              return InkWell(
                borderRadius: BorderRadius.circular(15),
                onTap: () => openRecordEditSheet(
                  context: context,
                  appState: appState,
                  goal: goal,
                  dayKey: key,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(15),
                    border: isToday ? Border.all(color: kBlue, width: 3) : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(emoji, style: const TextStyle(fontSize: 20)),
                      Text(
                        '$dayNumber',
                        style: const TextStyle(
                          fontSize: 10,
                          color: kMuted,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              LegendItem('🌟 本目標'),
              LegendItem('✅ サブ'),
              LegendItem('🐌🫠 未記録'),
              LegendItem('☁️ 未達'),
            ],
          ),
        ],
      ),
    );
  }
}

class GoalsPage extends StatelessWidget {
  const GoalsPage({super.key, required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final goals = appState.goals;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('設定中の目標', style: TextStyle(color: kMuted, fontWeight: FontWeight.w800)),
                  SizedBox(height: 4),
                  Text(
                    '目標',
                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -1.6),
                  ),
                ],
              ),
            ),
            RoundIconButton(
              icon: '+',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => GoalEditPage(appState: appState)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SummaryStatsCard(appState: appState),
        const SizedBox(height: 20),
        const SectionTitle(title: '目標一覧', right: '編集・停止・再開'),
        if (goals.isEmpty)
          EmptyPanel(
            title: 'まだ目標がありません',
            text: '最初の目標を作りましょう。',
            buttonText: '＋ 目標を作る',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => GoalEditPage(appState: appState)),
            ),
          )
        else
          ...goals.map(
            (goal) => GoalManageCard(appState: appState, goal: goal),
          ),
      ],
    );
  }
}

class SummaryStatsCard extends StatelessWidget {
  const SummaryStatsCard({super.key, required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final active = appState.activeGoals.length;
    final totalStamps = appState.records.values.length;
    final mainCount = appState.records.values.where((r) => r.status == RecordStatus.main).length;

    return BaseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('現在走っている目標', style: TextStyle(color: kMuted, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: StatTile(emoji: '🎯', number: '$active', label: '有効')),
              const SizedBox(width: 8),
              Expanded(child: StatTile(emoji: '🏷', number: '$totalStamps', label: '累計シール')),
              const SizedBox(width: 8),
              Expanded(child: StatTile(emoji: '🌟', number: '$mainCount', label: '本目標')),
            ],
          ),
        ],
      ),
    );
  }
}

class GoalManageCard extends StatelessWidget {
  const GoalManageCard({
    super.key,
    required this.appState,
    required this.goal,
  });

  final AppState appState;
  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final percent = appState.mainPercentLast30(goal);
    final percentText = '${(percent * 100).round()}%';
    final main = appState.countMainLast30(goal);
    final sub = appState.countSubLast30(goal);
    final streak = appState.streak(goal);

    return BaseGoalCard(
      borderColor: goal.isActive ? const Color(0xFFE6EDF5) : const Color(0xFFE5E7EB),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GoalCardHeader(
            name: goal.name,
            badge: goal.isActive ? '有効' : '停止中',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: kYellow,
                  borderRadius: BorderRadius.circular(999),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Text(
                  '🔥 $streak日',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'サブ以上で継続',
                style: TextStyle(color: kMuted.withOpacity(0.9), fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            '本目標達成率（直近30日）',
            style: TextStyle(fontSize: 12, color: kMuted, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 12,
              backgroundColor: const Color(0xFFE5E7EB),
              color: kBlue,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '$percentText（$main / 30日）',
            style: const TextStyle(color: Color(0xFF0369A1), fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('🌟 $main', style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(width: 14),
              Text('✅ $sub', style: const TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 14),
          TargetBox(label: '本目標', text: goal.mainTarget, color: kYellow),
          const SizedBox(height: 8),
          TargetBox(label: 'サブ目標', text: goal.subTarget, color: kGreen),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: '編集',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GoalEditPage(appState: appState, goal: goal),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SecondaryButton(
                  label: goal.isActive ? '停止' : '再開',
                  onTap: () async {
                    if (goal.isActive) {
                      await appState.stopGoal(goal);
                    } else {
                      await appState.resumeGoal(goal);
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class GoalEditPage extends StatefulWidget {
  const GoalEditPage({
    super.key,
    required this.appState,
    this.goal,
  });

  final AppState appState;
  final Goal? goal;

  @override
  State<GoalEditPage> createState() => _GoalEditPageState();
}

class _GoalEditPageState extends State<GoalEditPage> {
  late final TextEditingController name;
  late final TextEditingController mainTarget;
  late final TextEditingController subTarget;
  late final TextEditingController notificationTime;

  @override
  void initState() {
    super.initState();
    final g = widget.goal;
    name = TextEditingController(text: g?.name ?? '');
    mainTarget = TextEditingController(text: g?.mainTarget ?? '');
    subTarget = TextEditingController(text: g?.subTarget ?? '');
    notificationTime = TextEditingController(text: g?.notificationTime ?? '21:00');
  }

  @override
  void dispose() {
    name.dispose();
    mainTarget.dispose();
    subTarget.dispose();
    notificationTime.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.goal != null;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        title: Text(isEdit ? '目標を編集' : '目標を作る'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          BaseCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '1目標 = 本目標 + 絶対できるサブ目標',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 14),
                AppTextField(
                  controller: name,
                  label: '目標名',
                  hint: '例：筋トレ',
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: mainTarget,
                  label: '本目標',
                  hint: '例：30分筋トレ',
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: subTarget,
                  label: 'サブ目標',
                  hint: '例：1分筋トレ',
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: notificationTime,
                  label: '通知時間',
                  hint: '例：21:00',
                ),
                const SizedBox(height: 18),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: kText,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  onPressed: () async {
                    final n = name.text.trim();
                    final m = mainTarget.text.trim();
                    final s = subTarget.text.trim();
                    final t = notificationTime.text.trim();

                    if (n.isEmpty || m.isEmpty || s.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('目標名・本目標・サブ目標を入力してください')),
                      );
                      return;
                    }

                    if (isEdit) {
                      final goal = widget.goal!;
                      goal.name = n;
                      goal.mainTarget = m;
                      goal.subTarget = s;
                      goal.notificationTime = t.isEmpty ? '21:00' : t;
                      await widget.appState.updateGoal(goal);
                    } else {
                      await widget.appState.addGoal(
                        name: n,
                        mainTarget: m,
                        subTarget: s,
                        notificationTime: t.isEmpty ? '21:00' : t,
                      );
                    }

                    if (context.mounted) Navigator.pop(context);
                  },
                  child: Text(isEdit ? '保存する' : '作成する'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> openMemoSheet({
  required BuildContext context,
  required String title,
  required String emoji,
  required Future<void> Function(String memo) onSave,
}) async {
  final controller = TextEditingController();

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          18,
          16,
          MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 38)),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: '一言メモ（任意）',
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: kText,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              onPressed: () async {
                await onSave(controller.text.trim());
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('記録する'),
            ),
            TextButton(
              onPressed: () async {
                await onSave('');
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('メモなしで記録'),
            ),
          ],
        ),
      );
    },
  );

  controller.dispose();
}

Future<void> openRecordEditSheet({
  required BuildContext context,
  required AppState appState,
  required Goal goal,
  required String dayKey,
}) async {
  final current = appState.recordFor(goal.id, dayKey);
  final memo = TextEditingController(text: current?.memo ?? '');

  Future<void> save(RecordStatus status, {String? autoStamp}) async {
    await appState.upsertRecord(
      goalId: goal.id,
      dayKey: dayKey,
      status: status,
      memo: memo.text.trim(),
      autoStamp: autoStamp,
    );
    if (context.mounted) Navigator.pop(context);
  }

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          18,
          16,
          MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(dayKey, style: const TextStyle(color: kMuted, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(goal.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            TextField(
              controller: memo,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: '一言メモ（任意）',
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: StampButton(
                    emoji: '🌟',
                    label: '本目標',
                    color: kYellow,
                    onTap: () => save(RecordStatus.main),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StampButton(
                    emoji: '✅',
                    label: 'サブ',
                    color: kGreen,
                    onTap: () => save(RecordStatus.sub),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StampButton(
                    emoji: '☁️',
                    label: '未達',
                    color: kGray,
                    onTap: () => save(RecordStatus.miss),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: kAutoStamps.map((stamp) {
                return ActionChip(
                  label: Text('$stamp 未記録'),
                  onPressed: () => save(RecordStatus.auto, autoStamp: stamp),
                );
              }).toList(),
            ),
          ],
        ),
      );
    },
  );

  memo.dispose();
}

class BaseCard extends StatelessWidget {
  const BaseCard({
    super.key,
    required this.child,
    this.borderColor,
  });

  final Widget child;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: borderColor ?? Colors.transparent, width: 2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF141E32).withOpacity(0.08),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: child,
    );
  }
}

class BaseGoalCard extends StatelessWidget {
  const BaseGoalCard({
    super.key,
    required this.child,
    this.borderColor,
  });

  final Widget child;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: BaseCard(
        borderColor: borderColor ?? const Color(0xFFE6EDF5),
        child: child,
      ),
    );
  }
}

class GoalCardHeader extends StatelessWidget {
  const GoalCardHeader({
    super.key,
    required this.name,
    required this.badge,
  });

  final String name;
  final String badge;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            name,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -1.0),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: kGray,
            borderRadius: BorderRadius.circular(999),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Text(
            badge,
            style: const TextStyle(color: kMuted, fontSize: 12, fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class TargetBox extends StatelessWidget {
  const TargetBox({
    super.key,
    required this.label,
    required this.text,
    required this.color,
  });

  final String label;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: kMuted, fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class StampButton extends StatelessWidget {
  const StampButton({
    super.key,
    required this.emoji,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 23)),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
        ),
      ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kGray,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Center(
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ),
      ),
    );
  }
}

class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.onTap,
  });

  final String icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kText,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Text(icon, style: const TextStyle(color: Colors.white, fontSize: 30)),
          ),
        ),
      ),
    );
  }
}

class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.title,
    required this.big,
    required this.suffix,
    required this.caption,
  });

  final String title;
  final String big;
  final String suffix;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return BaseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: kMuted, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: const TextStyle(color: kText),
              children: [
                TextSpan(
                  text: big,
                  style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900),
                ),
                TextSpan(
                  text: ' $suffix',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(caption, style: const TextStyle(color: kMuted, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
    required this.right,
  });

  final String title;
  final String right;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.8),
            ),
          ),
          Text(
            right,
            style: const TextStyle(fontSize: 12, color: kMuted, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({
    super.key,
    required this.title,
    required this.text,
    this.buttonText,
    this.onTap,
  });

  final String title;
  final String text;
  final String? buttonText;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return BaseCard(
      child: Column(
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: kMuted, fontWeight: FontWeight.w800, height: 1.45),
          ),
          if (buttonText != null) ...[
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: kText,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              onPressed: onTap,
              child: Text(buttonText!),
            ),
          ],
        ],
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.emoji,
    required this.number,
    required this.label,
  });

  final String emoji;
  final String number;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(18)),
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 21)),
          Text(number, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          Text(label, style: const TextStyle(fontSize: 10, color: kMuted, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class Dow extends StatelessWidget {
  const Dow(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w900),
      ),
    );
  }
}

class LegendItem extends StatelessWidget {
  const LegendItem(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Text(
        text,
        style: const TextStyle(color: Color(0xFF475569), fontSize: 12, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
  });

  final TextEditingController controller;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
