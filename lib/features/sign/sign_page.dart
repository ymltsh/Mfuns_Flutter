import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../home/home_repository.dart';
import '../user/user_profile_page.dart';

AppPalette _palette(BuildContext context) => AppPalette.of(context);

class SignPage extends StatefulWidget {
  const SignPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SignPage> createState() => _SignPageState();
}

class _SignPageState extends State<SignPage> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    widget.controller.loadSignAwards();
    widget.controller.loadSignRank();
    if (widget.controller.session != null) {
      widget.controller.loadSignInfo();
    }
  }

  Future<void> _sign() async {
    if (widget.controller.session == null) {
      _notice('请先登录后再签到');
      return;
    }
    try {
      final message = await widget.controller.sign();
      if (mounted) _notice(message.isEmpty ? '签到成功' : message);
    } catch (error) {
      if (mounted) _notice('签到失败：$error');
    }
  }

  Future<void> _signAgain(int day) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('补签确认'),
        content: Text('将使用一张补签卡补签本月 $day 日，确定吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('补签'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.controller.signAgain(day);
      if (mounted) _notice('补签成功');
    } catch (error) {
      if (mounted) _notice('补签失败：$error');
    }
  }

  void _notice(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('每日签到'), centerTitle: true),
        body: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            final signInfo = widget.controller.signInfo;
            final today = DateTime.now();
            final isLandscape =
                MediaQuery.orientationOf(context) == Orientation.landscape;
            final status = _SignStatusCard(
              signInfo: signInfo,
              signedToday: signInfo?.signedDays.contains(today.day) ?? false,
              isSigning: widget.controller.isSigning,
              loading: widget.controller.isLoadingSignInfo,
              error: widget.controller.signInfoError,
              onSign: _sign,
            );
            final rank = _SignRankCard(
              items: widget.controller.signRank,
              loading: widget.controller.isLoadingSignRank,
              error: widget.controller.signRankError,
              controller: widget.controller,
            );
            final calendar = _SignCalendar(
              month: DateTime(today.year, today.month),
              signedDays: signInfo?.signedDays ?? const [],
              onSignAgain: _signAgain,
            );
            final awards = _SignAwardsCard(
              awards: widget.controller.signAwards,
              allTimes: signInfo?.allTimes ?? 0,
            );
            // 横屏双栏布局：左侧签到操作，右侧签到日历（自适应列宽）。
            if (isLandscape) {
              final panelWidth =
                  (MediaQuery.sizeOf(context).width * 0.42).clamp(300.0, 460.0);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(14, 14, 7, 32),
                      children: [
                        status,
                        const SizedBox(height: 12),
                        rank,
                        const SizedBox(height: 12),
                        awards,
                      ],
                    ),
                  ),
                  SizedBox(
                    width: panelWidth,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(7, 14, 14, 32),
                      children: [calendar],
                    ),
                  ),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
              children: [
                status,
                const SizedBox(height: 12),
                rank,
                const SizedBox(height: 12),
                calendar,
                const SizedBox(height: 12),
                awards,
              ],
            );
          },
        ),
      );
}

class _SignStatusCard extends StatelessWidget {
  const _SignStatusCard({
    required this.signInfo,
    required this.signedToday,
    required this.isSigning,
    required this.loading,
    required this.error,
    required this.onSign,
  });

  final SignInfo? signInfo;
  final bool signedToday;
  final bool isSigning;
  final bool loading;
  final String? error;
  final VoidCallback onSign;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            children: [
              Row(
                children: [
                  _SignStat(label: '本月签到', value: signInfo?.monthTimes),
                  const SizedBox(width: 10),
                  Container(
                      width: 1,
                      height: 30,
                      color: AppPalette.of(context).divider),
                  const SizedBox(width: 10),
                  _SignStat(label: '累计签到', value: signInfo?.allTimes),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed:
                        signedToday || isSigning || loading ? null : onSign,
                    icon: isSigning
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Icon(signedToday
                            ? Icons.check_rounded
                            : Icons.edit_calendar_rounded),
                    label: Text(signedToday ? '今日已签到' : '立即签到'),
                  ),
                ],
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 15, color: AppPalette.of(context).muted),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(error!,
                          style: TextStyle(
                              color: AppPalette.of(context).muted,
                              fontSize: 12.5)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
}

class _SignStat extends StatelessWidget {
  const _SignStat({required this.label, required this.value});

  final String label;
  final int? value;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text('${value ?? '—'}',
              style: TextStyle(
                  color: AppPalette.of(context).ink,
                  fontSize: 19,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: AppPalette.of(context).muted, fontSize: 11.5)),
        ],
      );
}

class _SignRankCard extends StatelessWidget {
  const _SignRankCard({
    required this.items,
    required this.loading,
    required this.error,
    required this.controller,
  });

  final List<SignRankEntry> items;
  final bool loading;
  final String? error;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final top = items.take(3).toList(growable: false);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 12, 8, 4),
            child: Row(
              children: [
                const Icon(Icons.emoji_events_rounded,
                    size: 17, color: Color(0xFFE6A23C)),
                const SizedBox(width: 6),
                Text('今日签到排行',
                    style: TextStyle(
                        color: AppPalette.of(context).ink,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800)),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SignRankPage(controller: controller),
                    ),
                  ),
                  child: const Text('完整排行'),
                ),
              ],
            ),
          ),
          if (loading && items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 22),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
            )
          else if (error != null && items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 22),
              child: Center(
                  child: Text(error!,
                      style: TextStyle(
                          color: AppPalette.of(context).muted,
                          fontSize: 12.5))),
            )
          else if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 22),
              child: Center(
                  child: Text('今天还没有人签到',
                      style: TextStyle(
                          color: AppPalette.of(context).muted,
                          fontSize: 12.5))),
            )
          else
            for (final (index, entry) in top.indexed) ...[
              if (index > 0) const Divider(height: 1, indent: 56),
              _SignRankRow(
                rank: index + 1,
                entry: entry,
                controller: controller,
              ),
            ],
        ],
      ),
    );
  }
}

class _SignCalendar extends StatelessWidget {
  const _SignCalendar({
    required this.month,
    required this.signedDays,
    required this.onSignAgain,
  });

  final DateTime month;
  final List<int> signedDays;
  final ValueChanged<int> onSignAgain;

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final firstWeekday = DateTime(month.year, month.month, 1).weekday;
    final today = DateTime.now();
    final isCurrentMonth =
        today.year == month.year && today.month == month.month;
    final todayDay = isCurrentMonth ? today.day : null;
    bool isPastDay(int day) => todayDay != null && day < todayDay;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 13, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('本月签到日历',
                    style: TextStyle(
                        color: AppPalette.of(context).ink,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800)),
                const Spacer(),
                Text('${month.year} 年 ${month.month} 月',
                    style: TextStyle(
                        color: AppPalette.of(context).muted, fontSize: 12.5)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: ['一', '二', '三', '四', '五', '六', '日']
                  .map((label) => Expanded(
                        child: Center(
                          child: Text(label,
                              style: TextStyle(
                                  color: AppPalette.of(context).muted,
                                  fontSize: 11)),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 4),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var i = 1; i < firstWeekday; i++) const SizedBox.shrink(),
                for (var day = 1; day <= daysInMonth; day++)
                  _SignDayCell(
                    day: day,
                    signed: signedDays.contains(day),
                    isToday: todayDay == day,
                    inPast: isPastDay(day),
                    onTap: signedDays.contains(day) ||
                            todayDay == day ||
                            !isPastDay(day)
                        ? null
                        : () => onSignAgain(day),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SignDayCell extends StatelessWidget {
  const _SignDayCell({
    required this.day,
    required this.signed,
    required this.isToday,
    required this.inPast,
    required this.onTap,
  });

  final int day;
  final bool signed;
  final bool isToday;
  final bool inPast;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    const signedColor = Color(0xFF4FA36C);
    final Color foreground;
    final Color background;
    final BoxDecoration? decoration;
    if (signed) {
      foreground = Colors.white;
      background = signedColor;
      decoration = BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
              color: background.withOpacity(.4),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      );
    } else {
      foreground = isToday
          ? palette.primary
          : AppPalette.of(context).muted.withOpacity(.6);
      background = Colors.transparent;
      decoration = isToday
          ? BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: palette.primary, width: 1.4),
            )
          : null;
    }
    return Center(
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: decoration,
          child: Text(
            '$day',
            style: TextStyle(
              color: foreground,
              fontSize: 12.5,
              fontWeight: signed ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _SignAwardsCard extends StatelessWidget {
  const _SignAwardsCard({required this.awards, required this.allTimes});

  final Map<int, List<SignAward>> awards;
  final int allTimes;

  @override
  Widget build(BuildContext context) {
    final entries = awards.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 13, 15, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('累计签到奖励',
                style: TextStyle(
                    color: AppPalette.of(context).ink,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text('奖励配置暂未加载',
                    style: TextStyle(
                        color: AppPalette.of(context).muted, fontSize: 12.5)),
              )
            else
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _palette(context).primary.withOpacity(.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('累计 ${entry.key} 天',
                            style: TextStyle(
                                color: _palette(context).primary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          entry.value.map((award) => award.desc).join(' + '),
                          style: TextStyle(
                              color: AppPalette.of(context).ink,
                              fontSize: 12.5),
                        ),
                      ),
                      if (allTimes >= entry.key)
                        const Icon(Icons.check_circle_rounded,
                            size: 15, color: Color(0xff4fa36c)),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class SignRankPage extends StatefulWidget {
  const SignRankPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SignRankPage> createState() => _SignRankPageState();
}

class _SignRankPageState extends State<SignRankPage> {
  @override
  void initState() {
    super.initState();
    widget.controller.loadSignRank();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('今日签到排行'), centerTitle: true),
        body: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            if (widget.controller.isLoadingSignRank &&
                widget.controller.signRank.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            final error = widget.controller.signRankError;
            if (error != null && widget.controller.signRank.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(error,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppPalette.of(context).muted)),
                ),
              );
            }
            final items = widget.controller.signRank;
            if (items.isEmpty) {
              return Center(
                child: Text('今天还没有人签到',
                    style: TextStyle(color: AppPalette.of(context).muted)),
              );
            }
            final list = RefreshIndicator(
              color: _palette(context).primary,
              onRefresh: widget.controller.loadSignRank,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) => Card(
                  clipBehavior: Clip.antiAlias,
                  child: _SignRankRow(
                    rank: index + 1,
                    entry: items[index],
                    controller: widget.controller,
                  ),
                ),
              ),
            );
            // 横屏宽屏时限制列表宽度并居中，避免行内容被过度拉伸。
            if (MediaQuery.orientationOf(context) != Orientation.landscape) {
              return list;
            }
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: list,
              ),
            );
          },
        ),
      );
}

class _SignRankRow extends StatelessWidget {
  const _SignRankRow({
    required this.rank,
    required this.entry,
    required this.controller,
  });

  final int rank;
  final SignRankEntry entry;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    final rankColor = switch (rank) {
      1 => const Color(0xFFE6A23C),
      2 => const Color(0xFF9AA0A8),
      3 => const Color(0xFFD29062),
      _ => AppPalette.of(context).muted,
    };
    final nameColor = switch (entry.nameColor) {
      'red' => const Color(0xFFE04F4F),
      _ => AppPalette.of(context).ink,
    };
    return ListTile(
      onTap: entry.userId == 0
          ? null
          : () {
              final userId = entry.userId;
              Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => UserProfilePage(
                  controller: controller,
                  userId: userId,
                ),
              ));
            },
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 26,
            child: Text('$rank',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: rankColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 18,
            backgroundColor: palette.primary.withOpacity(.12),
            foregroundImage:
                entry.avatar.isEmpty ? null : NetworkImage(entry.avatar),
            foregroundColor: palette.primary,
            child: Text(entry.name.isEmpty ? 'U' : entry.name[0]),
          ),
        ],
      ),
      title: Text(entry.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: nameColor, fontSize: 14, fontWeight: FontWeight.w700)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_today_rounded,
              size: 13, color: AppPalette.of(context).muted),
          const SizedBox(width: 4),
          Text('${entry.count} 天',
              style: TextStyle(
                  color: AppPalette.of(context).muted, fontSize: 12.5)),
        ],
      ),
    );
  }
}
