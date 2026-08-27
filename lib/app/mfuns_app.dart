import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';
import '../core/widgets/content_link_handler.dart';
import '../core/widgets/content_spans.dart';
import '../core/widgets/image_preview_page.dart';
import '../features/auth/auth_repository.dart';
import '../features/contribute/submissions_page.dart';
import '../features/sign/sign_page.dart';
import '../features/user/assets_page.dart';
import '../features/feed/feed_compose_page.dart';
import '../features/home/home_repository.dart';
import '../features/latest/latest_mfuns_repository.dart';
import '../features/message/messages_page.dart';
import '../features/message/notifications_page.dart';
import '../features/settings/settings_page.dart';
import '../features/user/user_profile_page.dart';
import '../features/video/content_detail_page.dart';
import 'app_controller.dart';

const Color _ink = Colors.blueGrey;
const Color _muted = Colors.blueGrey;

AppPalette _palette(BuildContext context) => AppPalette.of(context);

class MfunsApp extends StatefulWidget {
  const MfunsApp({
    super.key,
    required this.controller,
    this.navigatorKey,
  });

  final AppController controller;

  /// 全局导航 key：供链接唤醒等外部导航使用。
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<MfunsApp> createState() => _MfunsAppState();
}

class _MfunsAppState extends State<MfunsApp> {
  Color _seed = const Color(0xFF5094B2);

  @override
  void initState() {
    super.initState();
    widget.controller.initialize();
    ThemeSettings.load().then((color) {
      if (mounted) setState(() => _seed = color);
    });
  }

  void _setSeed(Color color) {
    setState(() => _seed = color);
    ThemeSettings.save(color);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Mfuns Flutter',
        debugShowCheckedModeBanner: false,
        navigatorKey: widget.navigatorKey,
        theme: buildAppTheme(_seed),
        home: _HomeShell(
          controller: widget.controller,
          themeSeed: _seed,
          onThemeChanged: _setSeed,
        ),
      );
}

class _HomeShell extends StatefulWidget {
  const _HomeShell({
    required this.controller,
    required this.themeSeed,
    required this.onThemeChanged,
  });

  final AppController controller;
  final Color themeSeed;
  final ValueChanged<Color> onThemeChanged;

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  var _index = 0;
  final _discoverKey = GlobalKey<_DiscoverPageState>();
  final _timelineKey = GlobalKey<_TimelinePageState>();
  final _messageKey = GlobalKey<_MessageCenterPageState>();

  @override
  void initState() {
    super.initState();
    widget.controller.homeTabRequest.addListener(_onTabRequest);
    // 冷启动（App 由点击通知拉起）时请求先于本页面构建已发生，
    // 构建后补应用跳转目标。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final value = widget.controller.homeTabRequest.value;
      if (value != 0 && value != _index) {
        setState(() => _index = value);
      }
    });
  }

  @override
  void dispose() {
    widget.controller.homeTabRequest.removeListener(_onTabRequest);
    super.dispose();
  }

  /// 通知点击等外部请求切换底部标签。
  void _onTabRequest() {
    if (!mounted) return;
    setState(() => _index = widget.controller.homeTabRequest.value);
  }

  /// 切到消息中心时立即刷新未读数，已读后小红点自动消失。
  void _switchTab(int value) {
    setState(() => _index = value);
    if (value == 2) widget.controller.refreshUnreadCounts();
  }

  Future<void> _refreshActiveTab() async {
    widget.controller.refreshUnreadCounts();
    switch (_index) {
      case 1:
        return _timelineKey.currentState?.refreshActiveTab() ??
            Future.value();
      case 2:
        return _messageKey.currentState?.reloadActiveTab() ??
            Future.value();
      default:
        return _discoverKey.currentState?.refreshActiveTab() ??
            widget.controller.refreshHome();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _DiscoverPage(controller: widget.controller, key: _discoverKey),
      _TimelinePage(controller: widget.controller, key: _timelineKey),
      _MessageCenterPage(controller: widget.controller, key: _messageKey),
      _ProfilePage(
        controller: widget.controller,
        themeSeed: widget.themeSeed,
        onThemeChanged: widget.onThemeChanged,
      ),
    ];
    final content = Column(
      children: [
        _Masthead(
          showTabs: false,
          onSearch: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _SearchPage(controller: widget.controller),
            ),
          ),
          onRefresh: _refreshActiveTab,
        ),
        Expanded(child: IndexedStack(index: _index, children: pages)),
      ],
    );
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    // 监听 controller：未读小红点随轮询结果即时刷新。
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final hasUnread = widget.controller.unreadCount > 0;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          // 横屏时底栏自动变为左侧垂直导航，充分利用宽屏空间。
          child: isLandscape
              ? Scaffold(
                  body: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SideRail(
                        index: _index,
                        onChanged: _switchTab,
                        hasUnread: hasUnread,
                      ),
                      Expanded(child: content),
                    ],
                  ),
                )
              : Scaffold(
                  body: content,
                  bottomNavigationBar: _BottomNavigation(
                    index: _index,
                    onChanged: _switchTab,
                    hasUnread: hasUnread,
                  ),
                ),
        );
      },
    );
  }
}

/// 横屏左侧垂直导航栏。
class _SideRail extends StatelessWidget {
  const _SideRail({
    required this.index,
    required this.onChanged,
    required this.hasUnread,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final bool hasUnread;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    final items = [
      (Icons.home_outlined, Icons.home_rounded, '首页'),
      (Icons.auto_awesome_outlined, Icons.auto_awesome, '动态'),
      (Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, '消息'),
      (Icons.person_outline_rounded, Icons.person_rounded, '我的'),
    ];
    return Material(
      color: Colors.white,
      child: SafeArea(
        right: false,
        child: SizedBox(
          width: 75,
          child: Column(
            children: [
              const SizedBox(height: 8),
              for (var i = 0; i < items.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: InkWell(
                    onTap: () => onChanged(i),
                      child: Column(
                        children: [
                          _NavIcon(
                            showDot: i == 2 && hasUnread,
                            child: Icon(
                              i == index ? items[i].$2 : items[i].$1,
                              size: 23,
                              color: i == index
                                  ? palette.primary
                                  : const Color(0xff777681),
                            ),
                          ),
                          const SizedBox(height: 3),
                        Text(items[i].$3,
                            style: TextStyle(
                                fontSize: 11,
                                color: i == index
                                    ? palette.primary
                                    : const Color(0xff777681),
                                fontWeight: i == index
                                    ? FontWeight.w800
                                    : FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Masthead extends StatelessWidget {
  const _Masthead({
    required this.showTabs,
    required this.onSearch,
    required this.onRefresh,
  });

  final bool showTabs;
  final VoidCallback onSearch;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => Material(
        color: _palette(context).primary,
        child: Padding(
          // 沉浸式：主题色背景延伸到状态栏区域，内容下移到状态栏之下。
          padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
          child: Column(
            children: [
              SizedBox(
                height: 52,
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 18),
                      child: SizedBox(
                        height: 30,
                        child: Image.asset('assets/mfuns_logo.png',
                            fit: BoxFit.contain),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: '搜索',
                      onPressed: onSearch,
                      icon: const Icon(Icons.search_rounded),
                    ),
                    IconButton(
                      tooltip: '刷新推荐',
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    const SizedBox(width: 6),
                  ],
                ),
              ),
              if (showTabs)
                const SizedBox(
                  height: 42,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _MastheadTab('推荐', true),
                      _MastheadTab('排行', false),
                      _MastheadTab('分区', false),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
}

class _MastheadTab extends StatelessWidget {
  const _MastheadTab(this.label, this.selected);

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(label,
                style: TextStyle(
                    color: Colors.white.withOpacity(selected ? 1 : .68),
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
            const SizedBox(height: 8),
            Container(
              height: 3,
              decoration: BoxDecoration(
                color: selected ? Colors.white : Colors.transparent,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ),
          ],
        ),
      );
}

class _BottomNavigation extends StatelessWidget {
  const _BottomNavigation({
    required this.index,
    required this.onChanged,
    required this.hasUnread,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final bool hasUnread;

  @override
  Widget build(BuildContext context) => BottomNavigationBar(
        currentIndex: index,
        onTap: onChanged,
        type: BottomNavigationBarType.fixed,
        elevation: 12,
        backgroundColor: Colors.white,
        selectedItemColor: _palette(context).primary,
        unselectedItemColor: const Color(0xff777681),
        selectedFontSize: 12,
        unselectedFontSize: 12,
        items: [
          const BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded),
              label: '首页'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.auto_awesome_outlined),
              activeIcon: Icon(Icons.auto_awesome),
              label: '动态'),
          BottomNavigationBarItem(
              icon: _NavIcon(
                showDot: hasUnread,
                child: const Icon(Icons.chat_bubble_outline_rounded),
              ),
              activeIcon: _NavIcon(
                showDot: hasUnread,
                child: const Icon(Icons.chat_bubble_rounded),
              ),
              label: '消息'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded),
              activeIcon: Icon(Icons.person_rounded),
              label: '我的'),
        ],
      );
}

/// 图标右上角的小红点（未读提示）。
class _NavIcon extends StatelessWidget {
  const _NavIcon({required this.child, required this.showDot});

  final Widget child;
  final bool showDot;

  @override
  Widget build(BuildContext context) => Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          if (showDot)
            const Positioned(
              right: -3,
              top: -3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: SizedBox(width: 7, height: 7),
              ),
            ),
        ],
      );
}

/// TabBarView 子页保活容器：保留滚动位置，避免切换标签重建。
class _KeepAliveTab extends StatefulWidget {
  const _KeepAliveTab({required this.child});

  final Widget child;

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _MessageCenterPage extends StatefulWidget {
  const _MessageCenterPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<_MessageCenterPage> createState() => _MessageCenterPageState();
}

class _MessageCenterPageState extends State<_MessageCenterPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  var _tab = 0;
  final _messagesKey = GlobalKey<MessageListPageState>();
  final _notificationsKey = GlobalKey<NotificationsPageState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(_syncTab);
    widget.controller.messageSubTabRequest.addListener(_onSubTabRequest);
    // 冷启动时请求可能先于本页面构建，构建后补应用。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onSubTabRequest();
    });
  }

  @override
  void dispose() {
    widget.controller.messageSubTabRequest.removeListener(_onSubTabRequest);
    _tabController.dispose();
    super.dispose();
  }

  /// 通知点击跳转：切到对应的私信/通知子标签。
  void _onSubTabRequest() {
    final value = widget.controller.messageSubTabRequest.value;
    if (value != _tab && _tabController.index != value) {
      _tabController.animateTo(value);
    }
  }

  /// 滑动切换私信/通知时同步高亮；进入“通知”页视为已读，立即刷新未读。
  void _syncTab() {
    if (_tabController.indexIsChanging) return;
    if (_tabController.index == _tab) return;
    setState(() => _tab = _tabController.index);
    if (_tabController.index == 1) {
      widget.controller.refreshUnreadCounts();
    }
  }

  /// Entry point for the shared masthead refresh button.
  Future<void> reloadActiveTab() {
    if (_tab == 0) {
      return _messagesKey.currentState?.reload() ?? Future.value();
    }
    return _notificationsKey.currentState?.reload() ?? Future.value();
  }

  @override
  Widget build(BuildContext context) => _PatternBackground(
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            if (widget.controller.session == null) {
              return _FollowingFeedState(
                icon: Icons.chat_bubble_outline_rounded,
                title: '登录后查看消息通知',
                subtitle: '私信、收到的赞、评论和@提及都在这里。',
                onLogin: () => _showLoginSheet(context, widget.controller),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('消息通知',
                            style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                color: _ink)),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _TimelineTabs(
                    index: _tab,
                    labels: const ['私信', '通知'],
                    badges: widget.controller.notifyUnread > 0
                        ? const {1}
                        : const <int>{},
                    onChanged: (value) => _tabController.animateTo(value),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _KeepAliveTab(
                        child: MessageListPage(
                          controller: widget.controller,
                          embedded: true,
                          key: _messagesKey,
                        ),
                      ),
                      _KeepAliveTab(
                        child: NotificationsPage(
                          controller: widget.controller,
                          embedded: true,
                          key: _notificationsKey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );
}

class _DiscoverPage extends StatefulWidget {
  const _DiscoverPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<_DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<_DiscoverPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  var _tab = 0;
  int? _categoryId;
  final _homeScroll = ScrollController();

  /// 最近一次刷新插入的新内容条数（信息流交界标记位置）。
  int _homeNewCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(_syncTab);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _homeScroll.dispose();
    super.dispose();
  }

  /// 刷新推荐流：记录新增条数，并在完成后回到最新内容顶部。
  Future<void> _refreshHome() async {
    final added = await widget.controller.refreshHome();
    if (added > 0 && mounted) setState(() => _homeNewCount = added);
    // 刷新完成后回到最新内容的最顶部（offset 0）。
    if (mounted && _homeScroll.hasClients) {
      _homeScroll.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  /// 点击交界标记：回到顶部查看新内容，并再次刷新。
  Future<void> _onHomeJunctionTap() async {
    if (_homeScroll.hasClients) {
      _homeScroll.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
    await _refreshHome();
  }

  /// 滑动切换标签时同步高亮并加载对应数据。
  void _syncTab() {
    if (_tabController.indexIsChanging) return;
    if (_tabController.index == _tab) return;
    setState(() => _tab = _tabController.index);
    _ensureLoaded(_tab);
  }

  Future<void> _ensureLoaded(int value) async {
    if (value == 1 && widget.controller.hotRankings.isEmpty) {
      await widget.controller.loadHotRankings();
    }
    if (value == 2) {
      if (widget.controller.categories.isEmpty) {
        await widget.controller.loadCategories();
      }
      if (!mounted ||
          widget.controller.categories.isEmpty ||
          _categoryId != null) {
        return;
      }
      await _selectCategory(widget.controller.categories.first.id);
    }
  }

  Future<void> _selectCategory(int categoryId) async {
    setState(() => _categoryId = categoryId);
    await widget.controller.loadCategoryContents(categoryId);
  }

  /// 刷新当前分区页激活的标签：推荐 / 排行 / 分区内容。
  Future<void> refreshActiveTab() {
    if (_tab == 0) return _refreshHome();
    if (_tab == 1) return widget.controller.loadHotRankings();
    final categoryId = _categoryId;
    if (categoryId != null) {
      return widget.controller.loadCategoryContents(categoryId);
    }
    return widget.controller.loadCategories();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final items = widget.controller.recommendations;
          return _PatternBackground(
            child: Column(
              children: [
                _SectionTabs(
                  index: _tab,
                  onChanged: (value) => _tabController.animateTo(value),
                ),
                // 分区标签条只在分区标签页显示。
                if (_tab == 2)
                  _CategoryStrip(
                    categories: widget.controller.categories,
                    selectedId: _categoryId,
                    onSelected: _selectCategory,
                  ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _KeepAliveTab(
                        child: RefreshIndicator(
                          color: _palette(context).accent,
                          onRefresh: _refreshHome,
                          child: _ContentGrid(
                            controller: widget.controller,
                            items: items,
                            isLoading: widget.controller.isLoadingHome,
                            error: widget.controller.homeError,
                            emptyText: '暂时没有推荐内容',
                            scrollController: _homeScroll,
                            junctionIndex:
                                _homeNewCount > 0 ? _homeNewCount : null,
                            onJunctionTap: _onHomeJunctionTap,
                          ),
                        ),
                      ),
                      _KeepAliveTab(
                        child: RefreshIndicator(
                          color: _palette(context).accent,
                          onRefresh: widget.controller.loadHotRankings,
                          child: _RankingList(
                            controller: widget.controller,
                            items: widget.controller.hotRankings,
                            loading: widget.controller.isLoadingHotRankings,
                            error: widget.controller.hotRankingsError,
                          ),
                        ),
                      ),
                      _KeepAliveTab(
                        child: RefreshIndicator(
                          color: _palette(context).accent,
                          onRefresh: refreshActiveTab,
                          child: _ContentGrid(
                            controller: widget.controller,
                            items: widget.controller.categoryContents,
                            isLoading:
                                widget.controller.isLoadingCategoryContents ||
                                    widget.controller.isLoadingCategories,
                            error: widget.controller.categoryContentsError ??
                                widget.controller.categoriesError,
                            emptyText: '请选择分区查看内容',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
}

class _SectionTabs extends StatelessWidget {
  const _SectionTabs({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        color: _palette(context).primary,
        height: 47,
        child: Row(
          children: ['推荐', '排行', '分区'].asMap().entries.map((entry) {
            final selected = entry.key == index;
            return Expanded(
              child: InkWell(
                onTap: () => onChanged(entry.key),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(entry.value,
                        style: TextStyle(
                            color: selected
                                ? Colors.white
                                : Colors.white.withOpacity(.68),
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500)),
                    const SizedBox(height: 8),
                    Container(
                      width: 28,
                      height: 3,
                      decoration: BoxDecoration(
                        color: selected ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      );
}

class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({
    required this.categories,
    required this.selectedId,
    required this.onSelected,
  });

  final List<CategoryNode> categories;
  final int? selectedId;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Container(
        height: 51,
        color: Colors.white,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          scrollDirection: Axis.horizontal,
          children: [
            if (categories.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Text('正在加载分区…', style: TextStyle(color: _muted)),
              ),
            ...categories.map((category) => _CategoryChip(
                  label: category.name,
                  selected: category.id == selectedId,
                  onTap: () => onSelected(category.id),
                )),
          ],
        ),
      );
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
          selectedColor: _palette(context).primary.withOpacity(.15),
          labelStyle: TextStyle(
            color: selected ? _palette(context).primary : _muted,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
          side: BorderSide.none,
          backgroundColor: const Color(0xfff4f3f8),
          shape: const StadiumBorder(),
        ),
      );
}

class _TimelinePage extends StatefulWidget {
  const _TimelinePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<_TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<_TimelinePage>
    with SingleTickerProviderStateMixin {
  /// 视觉位置 → 逻辑标签值：时间线(2) / 最新(1) / 关注(0)。
  static const _visualToTab = [2, 1, 0];
  late final TabController _tabController;
  var _tab = 2;
  final _feedScroll = ScrollController();
  final _latestScroll = ScrollController();
  final _followingScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(_syncTab);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.loadFeeds();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _feedScroll.dispose();
    _latestScroll.dispose();
    _followingScroll.dispose();
    super.dispose();
  }

  /// 滑动切换标签时同步高亮并加载对应数据。
  void _syncTab() {
    if (_tabController.indexIsChanging) return;
    final value = _visualToTab[_tabController.index];
    if (value == _tab) return;
    setState(() => _tab = value);
    _loadForTab(value);
  }

  Future<void> _loadForTab(int value) {
    if (value == 0) return widget.controller.loadFollowingFeeds();
    if (value == 1) return widget.controller.loadLatestItems();
    return widget.controller.loadFeeds();
  }

  /// 刷新完成后回到列表顶部（动态页点击刷新后应回到顶部查看最新内容）。
  Future<void> _refreshActiveTab() async {
    await _loadForTab(_tab);
    final controller = switch (_tab) {
      0 => _followingScroll,
      1 => _latestScroll,
      _ => _feedScroll,
    };
    if (controller.hasClients) {
      controller.animateTo(0,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  /// Entry point for the shared masthead refresh button.
  Future<void> refreshActiveTab() => _refreshActiveTab();

  Future<void> _loginForFollowing() async {
    await _showLoginSheet(context, widget.controller);
    if (mounted && widget.controller.session != null) {
      await widget.controller.loadFollowingFeeds();
    }
  }

  void _openUserProfile(int userId) {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) =>
            UserProfilePage(controller: widget.controller, userId: userId)));
  }

  void _openContentDetail(ContentPreview preview) {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ContentDetailPage(
            controller: widget.controller, preview: preview)));
  }

  void _openFeedDetail(int feedId) {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) =>
            FeedDetailPage(controller: widget.controller, feedId: feedId)));
  }

  void _openLatestItem(LatestMfunsItem item) {
    if (item.isArticle || item.isVideo) {
      _openContentDetail(item.contentPreview);
      return;
    }
    _openFeedDetail(item.id);
  }

  /// 不友好标记 / 取消标记（需登录）：长按最新页帖子 → 菜单选择。
  /// 标记 5 人后帖子被服务端屏蔽并从列表移除，因此在刷新前仍可取消。
  Future<void> _markLatestItem(LatestMfunsItem item) async {
    if (widget.controller.session == null) {
      await _showLoginSheet(context, widget.controller);
      return;
    }
    final cancel = item.markedByMe;
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: Text(cancel ? '取消不友好标记' : '不友好标记'),
        content: Text(cancel
            ? '取消后该帖子的标记数会减少；帖子被 5 人标记屏蔽后将无法取消。确定取消吗？'
            : '标记该帖子为不友好内容后，其他喵友也可标记；达到 5 人标记后，'
                '该帖子将被屏蔽处理。确定标记吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(cancel ? '取消标记' : '标记'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final result = cancel
          ? await widget.controller.unmarkLatestItem(item)
          : await widget.controller.markLatestItem(item);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(cancel
            ? '已取消标记'
            : result.blocked
                ? '该帖子已被 ${result.markCount} 位喵友标记，已屏蔽处理'
                : '标记成功，已有 ${result.markCount}/5 位喵友标记此帖子'),
      ));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('操作失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => _PatternBackground(
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('动态',
                          style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              color: _ink)),
                    ),
                    IconButton(
                      tooltip: '发布动态',
                      color: _palette(context).primary,
                      onPressed: () {
                        if (widget.controller.session == null) {
                          _showLoginSheet(context, widget.controller);
                          return;
                        }
                        Navigator.of(context)
                            .push<bool>(
                              MaterialPageRoute<bool>(
                                builder: (_) => FeedComposePage(
                                    controller: widget.controller),
                              ),
                            )
                            .then((changed) {
                          if (changed == true && mounted) {
                            _refreshActiveTab();
                          }
                        });
                      },
                      icon: const Icon(Icons.edit_note_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _TimelineTabs(
                  index: _tab,
                  labels: const ['时间线', '最新', '关注'],
                  order: _visualToTab,
                  onChanged: (value) =>
                      _tabController.animateTo(_visualToTab.indexOf(value)),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // 时间线
                    _KeepAliveTab(
                      child: RefreshIndicator(
                        color: _palette(context).accent,
                        onRefresh: _refreshActiveTab,
                        child: _TimelineFeedList(
                          controller: widget.controller,
                          items: widget.controller.feeds,
                          isLoading: widget.controller.isLoadingFeeds,
                          isLoadingMore:
                              widget.controller.isLoadingMoreFeeds,
                          hasMore: widget.controller.hasMoreFeeds,
                          error: widget.controller.feedsError,
                          onLoadMore: widget.controller.loadMoreFeeds,
                          onOpenUser: _openUserProfile,
                          onOpenResource: _openContentDetail,
                          onOpenFeed: _openFeedDetail,
                          emptyText: '时间线暂时没有可展示的动态',
                          scrollController: _feedScroll,
                        ),
                      ),
                    ),
                    // 最新
                    _KeepAliveTab(
                      child: RefreshIndicator(
                        color: _palette(context).accent,
                        onRefresh: _refreshActiveTab,
                        child: _LatestItemList(
                          items: widget.controller.latestItems,
                          isLoading: widget.controller.isLoadingLatestItems,
                          isLoadingMore:
                              widget.controller.isLoadingMoreLatestItems,
                          hasMore: widget.controller.hasMoreLatestItems,
                          error: widget.controller.latestItemsError,
                          onLoadMore: widget.controller.loadMoreLatestItems,
                          onOpenUser: _openUserProfile,
                          onOpenItem: _openLatestItem,
                          onMarkItem: _markLatestItem,
                          scrollController: _latestScroll,
                        ),
                      ),
                    ),
                    // 关注
                    widget.controller.session == null
                        ? _FollowingFeedState(
                            onLogin: _loginForFollowing,
                          )
                        : _KeepAliveTab(
                            child: RefreshIndicator(
                              color: _palette(context).accent,
                              onRefresh: _refreshActiveTab,
                              child: _TimelineFeedList(
                                controller: widget.controller,
                                items: widget.controller.followingFeeds,
                                isLoading:
                                    widget.controller.isLoadingFollowingFeeds,
                                isLoadingMore: widget.controller
                                    .isLoadingMoreFollowingFeeds,
                                hasMore:
                                    widget.controller.hasMoreFollowingFeeds,
                                error: widget.controller.followingFeedsError,
                                onLoadMore:
                                    widget.controller.loadMoreFollowingFeeds,
                                onOpenUser: _openUserProfile,
                                onOpenResource: _openContentDetail,
                                onOpenFeed: _openFeedDetail,
                                emptyText:
                                    '还没有关注动态，先去时间线发现创作者吧',
                                scrollController: _followingScroll,
                              ),
                            ),
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _LatestItemList extends StatelessWidget {
  const _LatestItemList({
    required this.items,
    required this.isLoading,
    required this.isLoadingMore,
    required this.hasMore,
    required this.error,
    required this.onLoadMore,
    required this.onOpenUser,
    required this.onOpenItem,
    required this.onMarkItem,
    this.scrollController,
  });

  final List<LatestMfunsItem> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;
  final Future<void> Function() onLoadMore;
  final ValueChanged<int> onOpenUser;
  final ValueChanged<LatestMfunsItem> onOpenItem;
  final ValueChanged<LatestMfunsItem> onMarkItem;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    if (isLoading && items.isEmpty) return const _LoadingState();
    if (error != null && items.isEmpty) return _MessageState(message: error!);
    if (items.isEmpty) {
      return const _MessageState(message: '最新内容暂时没有可展示的帖子');
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 220 &&
            hasMore &&
            !isLoadingMore) {
          onLoadMore();
        }
        return false;
      },
      child: ListView.separated(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 86),
        itemCount: items.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == items.length) {
            if (isLoadingMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (error != null) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: Text('加载更多失败：$error',
                      style: const TextStyle(color: _muted, fontSize: 12)),
                ),
              );
            }
            if (!hasMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: Text('已经到底了',
                      style: TextStyle(color: _muted, fontSize: 12)),
                ),
              );
            }
            return const SizedBox(height: 2);
          }
          return _LatestItemCard(
            item: items[index],
            onOpenUser: onOpenUser,
            onOpenItem: onOpenItem,
            onMarkItem: onMarkItem,
          );
        },
      ),
    );
  }
}

class _LatestItemCard extends StatefulWidget {
  const _LatestItemCard({
    required this.item,
    required this.onOpenUser,
    required this.onOpenItem,
    required this.onMarkItem,
  });

  final LatestMfunsItem item;
  final ValueChanged<int> onOpenUser;
  final ValueChanged<LatestMfunsItem> onOpenItem;
  final ValueChanged<LatestMfunsItem> onMarkItem;

  @override
  State<_LatestItemCard> createState() => _LatestItemCardState();
}

class _LatestItemCardState extends State<_LatestItemCard> {
  /// 已标记折叠后是否临时展开查看；刷新后默认回到折叠状态。
  var _expanded = false;

  @override
  void didUpdateWidget(_LatestItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 列表位置被复用时重置展开状态，避免串帖。
    if (oldWidget.item.stableId != widget.item.stableId) {
      _expanded = false;
    }
  }

  void _showMarkMenu(BuildContext context) {
    final item = widget.item;
    final cancel = item.markedByMe;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: cancel
                  ? const Icon(Icons.flag_rounded, color: Color(0xFF4FA36C))
                  : const Icon(Icons.flag_outlined,
                      color: Color(0xFFD29062)),
              title: Text(cancel ? '取消不友好标记' : '不友好标记'),
              subtitle: Text(cancel
                  ? '取消后该帖子的标记数会减少'
                  : '需登录：不友好内容标记，5 人标记后帖子将被屏蔽'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                widget.onMarkItem(item);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 折叠状态：自己标记过的帖子默认折叠，刷新后（服务端仍标记）保持折叠。
  bool get _collapsed => widget.item.markedByMe && !_expanded;

  Widget _collapsedRow(BuildContext context) {
    final item = widget.item;
    return GestureDetector(
      onTap: () => setState(() => _expanded = true),
      onLongPress: () => _showMarkMenu(context),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              const Icon(Icons.flag_rounded,
                  color: Color(0xFFD29062), size: 17),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '该帖子已被你折叠（不友好标记，${item.markCount}/5 位喵友已标记）',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 12.5),
                ),
              ),
              Text('展开',
                  style: TextStyle(
                      color: _palette(context).primary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_collapsed) return _collapsedRow(context);
    final item = widget.item;
    final title = item.title.isNotEmpty ? item.title : _latestExcerpt(item);
    final excerpt = _latestExcerpt(item);
    final typeLabel = item.isVideo
        ? '视频'
        : item.isArticle
            ? '文章'
            : '动态';
    return GestureDetector(
      onLongPress: () => _showMarkMenu(context),
      child: Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => widget.onOpenItem(item),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkResponse(
                onTap: item.authorId == null || item.authorId == 0
                    ? null
                    : () => widget.onOpenUser(item.authorId!),
                radius: 28,
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: _palette(context).primary.withOpacity(.12),
                  foregroundImage: item.authorAvatar.isEmpty
                      ? null
                      : NetworkImage(item.authorAvatar),
                  foregroundColor: _palette(context).primary,
                  child: Text(item.author.isEmpty ? 'M' : item.author[0]),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.author.isEmpty ? 'Mfuns 用户' : item.author,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _ink,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        _LatestTypeChip(label: typeLabel),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(_timelineTime(item.createdAt),
                        style: const TextStyle(color: _muted, fontSize: 12)),
                    const SizedBox(height: 8),
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: _ink,
                            fontWeight: FontWeight.w700,
                            height: 1.35)),
                    if (excerpt.isNotEmpty && excerpt != title) ...[
                      const SizedBox(height: 5),
                      Text(excerpt,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _ink, height: 1.4)),
                    ],
                    if (item.cover.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: AspectRatio(
                          aspectRatio: 16 / 8,
                          child: Image.network(
                            item.cover,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const ColoredBox(
                              color: Color(0xffefeff7),
                              child: Center(
                                child: Icon(Icons.broken_image_outlined,
                                    color: _muted),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      '${item.likes} 赞 · ${item.comments} 评论 · ${item.views} 浏览',
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                    if (item.markCount > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.flag_outlined,
                              size: 13, color: Color(0xFFD29062)),
                          const SizedBox(width: 4),
                          Text(
                            item.markedByMe
                                ? '我已标记 · 已有 ${item.markCount}/5 位喵友标记此帖子'
                                : '已有 ${item.markCount}/5 位喵友标记此帖子',
                            style: const TextStyle(
                                color: Color(0xFFD29062), fontSize: 11.5),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _LatestTypeChip extends StatelessWidget {
  const _LatestTypeChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: _palette(context).primary.withOpacity(.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(
                color: _palette(context).primary,
                fontSize: 11,
                fontWeight: FontWeight.w700)),
      );
}

String _latestExcerpt(LatestMfunsItem item) {
  final source = item.content.trim();
  return source
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _TimelineTabs extends StatelessWidget {
  const _TimelineTabs({
    required this.index,
    required this.onChanged,
    this.labels = const ['关注', '最新', '时间线'],
    this.order,
    this.badges = const <int>{},
  });

  final int index;
  final ValueChanged<int> onChanged;
  final List<String> labels;

  /// Display order as logical tab indices; defaults to `[0, 1, ...]`.
  final List<int>? order;

  /// Positions (in display order) that show a red unread dot.
  final Set<int> badges;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: const Color(0xffeeedf5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: List.generate(labels.length, (position) {
            final logical = (order ?? List.generate(labels.length, (i) => i))[position];
            final selected = logical == index;
            return Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () => onChanged(logical),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: selected ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: selected
                        ? const [
                            BoxShadow(color: Color(0x11000000), blurRadius: 4)
                          ]
                        : null,
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Text(labels[position],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: selected ? _palette(context).primary : _muted,
                              fontWeight:
                                  selected ? FontWeight.w800 : FontWeight.w600)),
                      if (badges.contains(position))
                        const Positioned(
                          right: -6,
                          top: -6,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: SizedBox(width: 7, height: 7),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      );
}

class _FollowingFeedState extends StatelessWidget {
  const _FollowingFeedState({
    required this.onLogin,
    this.icon = Icons.people_alt_outlined,
    this.title = '登录后查看关注动态',
    this.subtitle = '先去时间线发现感兴趣的创作者吧。',
  });

  final VoidCallback onLogin;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: _palette(context).primary.withOpacity(.11),
                foregroundColor: _palette(context).primary,
                child: Icon(icon, size: 30),
              ),
              const SizedBox(height: 14),
              Text(title,
                  style: const TextStyle(
                      color: _ink, fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(height: 6),
              Text(subtitle,
                  textAlign: TextAlign.center, style: const TextStyle(color: _muted)),
              const SizedBox(height: 14),
              FilledButton(onPressed: onLogin, child: const Text('登录')),
            ],
          ),
        ),
      );
}

class _TimelineFeedList extends StatelessWidget {
  const _TimelineFeedList({
    required this.items,
    required this.isLoading,
    required this.isLoadingMore,
    required this.hasMore,
    required this.error,
    required this.onLoadMore,
    required this.onOpenUser,
    required this.onOpenResource,
    required this.onOpenFeed,
    required this.emptyText,
    required this.controller,
    this.scrollController,
  });

  final List<TimelineFeed> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;
  final Future<void> Function() onLoadMore;
  final ValueChanged<int> onOpenUser;
  final ValueChanged<ContentPreview> onOpenResource;
  final ValueChanged<int> onOpenFeed;
  final String emptyText;
  final AppController controller;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    if (isLoading && items.isEmpty) return const _LoadingState();
    if (error != null && items.isEmpty) return _MessageState(message: error!);
    if (items.isEmpty) return _MessageState(message: emptyText);
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 220 &&
            hasMore &&
            !isLoadingMore) {
          onLoadMore();
        }
        return false;
      },
      child: ListView.separated(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 86),
        itemCount: items.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == items.length) {
            if (isLoadingMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (error != null) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: Text('加载更多失败：$error',
                      style: const TextStyle(color: _muted, fontSize: 12)),
                ),
              );
            }
            if (!hasMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Center(
                    child: Text('已经到底了',
                        style: TextStyle(color: _muted, fontSize: 12))),
              );
            }
            return const SizedBox(height: 2);
          }
          return _TimelineFeedCard(
            item: items[index],
            controller: controller,
            onOpenUser: onOpenUser,
            onOpenResource: onOpenResource,
            onOpenFeed: onOpenFeed,
          );
        },
      ),
    );
  }
}

class _TimelineFeedCard extends StatelessWidget {
  const _TimelineFeedCard({
    required this.item,
    required this.controller,
    required this.onOpenUser,
    required this.onOpenResource,
    required this.onOpenFeed,
  });

  final TimelineFeed item;
  final AppController controller;
  final ValueChanged<int> onOpenUser;
  final ValueChanged<ContentPreview> onOpenResource;
  final ValueChanged<int> onOpenFeed;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          // 自动同步动态（is_auto_sync）等价于 Web 端 302 跳转，
          // 点击直接打开对应的文章/视频页。
          onTap: () => item.isAutoSync && item.resource != null
              ? onOpenResource(item.resource!)
              : onOpenFeed(item.id),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkResponse(
                  onTap: item.authorId == null
                      ? null
                      : () => onOpenUser(item.authorId!),
                  radius: 28,
                  child: CircleAvatar(
                    radius: 19,
                    backgroundColor: _palette(context).primary.withOpacity(.12),
                    foregroundImage:
                        item.avatar.isEmpty ? null : NetworkImage(item.avatar),
                    foregroundColor: _palette(context).primary,
                    child: Text(item.author.isEmpty
                        ? 'M'
                        : item.author.substring(0, 1)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.author.isEmpty ? 'Mfuns 用户' : item.author,
                          style: const TextStyle(
                              color: _ink, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(_timelineTime(item.createdAt),
                          style: const TextStyle(color: _muted, fontSize: 12)),
                      const SizedBox(height: 9),
                      item.spans.isEmpty
                          ? Text(item.content,
                              maxLines: item.resource == null ? null : 4,
                              overflow: item.resource == null
                                  ? TextOverflow.visible
                                  : TextOverflow.ellipsis,
                              style:
                                  const TextStyle(color: _ink, height: 1.45))
                          : ContentSpans(
                              spans: item.spans,
                              onLinkTap: (url) => openContentLink(
                                  context, controller, url),
                              textStyle:
                                  const TextStyle(color: _ink, height: 1.45)),
                      if (item.resource != null) ...[
                        const SizedBox(height: 10),
                        _TimelineResourceCard(
                          item: item.resource!,
                          onTap: () => onOpenResource(item.resource!),
                        ),
                      ],
                      if (item.images.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 144,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: item.images.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, imageIndex) {
                              final uri =
                                  Uri.tryParse(item.images[imageIndex]);
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: GestureDetector(
                                  onTap: uri == null
                                      ? null
                                      : () => Navigator.of(context).push(
                                            MaterialPageRoute<void>(
                                              builder: (_) =>
                                                  ImagePreviewPage(
                                                uri: uri,
                                                alt: '动态图片',
                                                heroTag:
                                                    'feed-image-${item.id}-$imageIndex-$uri',
                                                uris: item.images
                                                    .map(Uri.parse)
                                                    .toList(growable: false),
                                                initialIndex: imageIndex,
                                              ),
                                            ),
                                          ),
                                  child: AspectRatio(
                                    aspectRatio: 1,
                                    child: Hero(
                                      tag: 'feed-image-${item.id}-$imageIndex-$uri',
                                      child: Image.network(
                                          item.images[imageIndex],
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const ColoredBox(
                                            color: Color(0xffefeff7),
                                            child: Center(
                                              child: Icon(
                                                  Icons.broken_image_outlined,
                                                  color: _muted),
                                            ),
                                          )),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.thumb_up_alt_outlined,
                              size: 16, color: _muted),
                          const SizedBox(width: 4),
                          Text('${item.likes}',
                              style:
                                  const TextStyle(color: _muted, fontSize: 12)),
                          const SizedBox(width: 18),
                          const Icon(Icons.mode_comment_outlined,
                              size: 16, color: _muted),
                          const SizedBox(width: 4),
                          Text('${item.comments}',
                              style:
                                  const TextStyle(color: _muted, fontSize: 12)),
                          const SizedBox(width: 18),
                          const Icon(Icons.visibility_outlined,
                              size: 16, color: _muted),
                          const SizedBox(width: 4),
                          Text('${item.views}',
                              style:
                                  const TextStyle(color: _muted, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// 自动同步动态的类型标识（文章/视频）。
class _FeedTypeTag extends StatelessWidget {
  const _FeedTypeTag({required this.isVideo});

  final bool isVideo;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: _palette(context).primary.withOpacity(.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(isVideo ? '视频' : '文章',
            style: TextStyle(
                color: _palette(context).primary,
                fontSize: 10.5,
                fontWeight: FontWeight.w700)),
      );
}

class _TimelineResourceCard extends StatelessWidget {
  const _TimelineResourceCard({required this.item, required this.onTap});

  final ContentPreview item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xfff4f4fa),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            height: 76,
            child: Row(
              children: [
                ClipRRect(
                  borderRadius:
                      const BorderRadius.horizontal(left: Radius.circular(10)),
                  child: SizedBox(
                    width: 108,
                    height: 76,
                    child: item.cover.isEmpty
                        ? const ColoredBox(
                            color: Color(0xffe6e6f0),
                            child: Icon(Icons.article_outlined, color: _muted),
                          )
                        : Image.network(item.cover, fit: BoxFit.cover),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: _ink, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Row(
                          children: [
                            _FeedTypeTag(isVideo: item.isVideo),
                            const SizedBox(width: 6),
                            Text('${item.views} 浏览 · ${item.likes} 赞',
                                style: const TextStyle(
                                    color: _muted, fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

String _timelineTime(DateTime? value) {
  if (value == null) return '刚刚';
  final now = DateTime.now();
  final difference = now.difference(value);
  if (difference.isNegative || difference.inMinutes < 1) return '刚刚';
  if (difference.inHours < 1) return '${difference.inMinutes} 分钟前';
  if (difference.inDays < 1) return '${difference.inHours} 小时前';
  if (difference.inDays < 7) return '${difference.inDays} 天前';
  return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

class _SearchPage extends StatefulWidget {
  const _SearchPage({required this.controller});

  final AppController controller;

  @override
  State<_SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<_SearchPage> {
  final _textController = TextEditingController();
  var _type = -1;

  /// 用户搜索的类型标识（与内容搜索区分）。
  static const _typeUser = 2;

  Future<void> _search([String? value]) {
    final query = value ?? _textController.text;
    return _type == _typeUser
        ? widget.controller.searchUser(query)
        : widget.controller.search(query, type: _type);
  }

  void _selectType(int type) {
    setState(() => _type = type);
    if (_textController.text.trim().isNotEmpty) _search();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('搜索'),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: _PatternBackground(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                child: TextField(
                  controller: _textController,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _search,
                  decoration: InputDecoration(
                    hintText: '搜索文章、视频和用户',
                    prefixIcon: const Icon(Icons.search_rounded, color: _muted),
                    suffixIcon: IconButton(
                      tooltip: '搜索',
                      onPressed: _search,
                      icon: Icon(Icons.arrow_forward_rounded,
                          color: _palette(context).primary),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _SearchTypeBar(
                  type: _type,
                  onChanged: _selectType,
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: _type == _typeUser
                    ? AnimatedBuilder(
                        animation: widget.controller,
                        builder: (context, _) => _UserSearchResults(
                          controller: widget.controller,
                          users: widget.controller.searchUserResults,
                          isLoading: widget.controller.isSearchingUser,
                          error: widget.controller.searchUserError,
                        ),
                      )
                    : AnimatedBuilder(
                        animation: widget.controller,
                        builder: (context, _) => _ContentGrid(
                          controller: widget.controller,
                          items: widget.controller.searchResults,
                          isLoading: widget.controller.isSearching,
                          error: widget.controller.searchError,
                          emptyText: '输入关键词，寻找同好',
                        ),
                      ),
              ),
            ],
          ),
        ),
      );
}

class _SearchTypeBar extends StatelessWidget {
  const _SearchTypeBar({required this.type, required this.onChanged});

  final int type;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: const [
          _SearchTypeItem(type: -1, label: '综合'),
          _SearchTypeItem(type: 0, label: '文章'),
          _SearchTypeItem(type: 1, label: '视频'),
          _SearchTypeItem(type: 2, label: '用户'),
        ].map((item) {
          final selected = item.type == type;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(item.label),
              selected: selected,
              onSelected: (_) => onChanged(item.type),
              selectedColor: _palette(context).primary.withOpacity(.14),
              labelStyle: TextStyle(
                  color: selected ? _palette(context).primary : _muted,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500),
              side: BorderSide.none,
              backgroundColor: Colors.white,
            ),
          );
        }).toList(),
      );
}

class _SearchTypeItem {
  const _SearchTypeItem({required this.type, required this.label});

  final int type;
  final String label;
}

/// 搜索页「用户」标签的结果列表：头像 + 用户名，点击进入用户主页。
class _UserSearchResults extends StatelessWidget {
  const _UserSearchResults({
    required this.controller,
    required this.users,
    required this.isLoading,
    required this.error,
  });

  final AppController controller;
  final List<UserProfile> users;
  final bool isLoading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    if (isLoading && users.isEmpty) return const _LoadingState();
    if (error != null && users.isEmpty) {
      return _MessageState(message: error!);
    }
    if (users.isEmpty) {
      return const _MessageState(message: '输入用户名，寻找同好');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: users.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 52),
      itemBuilder: (context, index) {
        final user = users[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: _palette(context).primary.withOpacity(.12),
            foregroundImage:
                user.avatar.isEmpty ? null : NetworkImage(user.avatar),
            foregroundColor: _palette(context).primary,
            child: Text(user.name.isEmpty ? 'U' : user.name[0]),
          ),
          title: Text(user.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: _ink, fontWeight: FontWeight.w700, fontSize: 15)),
          subtitle: user.bio.isEmpty
              ? null
              : Text(user.bio,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 12.5)),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) =>
                UserProfilePage(controller: controller, userId: user.id),
          )),
        );
      },
    );
  }
}

class _ProfilePage extends StatefulWidget {
  const _ProfilePage({
    required this.controller,
    required this.themeSeed,
    required this.onThemeChanged,
  });

  final AppController controller;
  final Color themeSeed;
  final ValueChanged<Color> onThemeChanged;

  @override
  State<_ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<_ProfilePage> {
  var _statsRequested = false;

  /// Loads history, favorite-folders and submission counts once the member
  /// is signed in so the stat cards show real numbers without a manual
  /// refresh.
  void _ensureStats() {
    if (_statsRequested) return;
    final controller = widget.controller;
    if (controller.session == null) return;
    _statsRequested = true;
    controller.loadHistory();
    controller.loadFavoriteFolders();
    controller.loadSubmissionCounts();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          if (widget.controller.session != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _ensureStats();
            });
          }
          final session = widget.controller.session;
          return _PatternBackground(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 28),
              children: [
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    color: _palette(context).primary,
                    borderRadius:
                        const BorderRadius.vertical(bottom: Radius.circular(26)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
                    child: session == null
                        ? _GuestProfile(
                            onLogin: () => _showLoginSheet(context, widget.controller))
                        : _SignedInProfile(
                            session: session,
                            controller: widget.controller,
                            themeSeed: widget.themeSeed,
                            onThemeChanged: widget.onThemeChanged),
                  ),
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: session == null
                      ? _ProfileGuestBody(
                          controller: widget.controller,
                          themeSeed: widget.themeSeed,
                          onThemeChanged: widget.onThemeChanged)
                      : _ProfileMemberBody(
                          controller: widget.controller,
                          themeSeed: widget.themeSeed,
                          onThemeChanged: widget.onThemeChanged),
                ),
              ],
            ),
          );
        },
      );
}

class _GuestProfile extends StatelessWidget {
  const _GuestProfile({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          CircleAvatar(
              radius: 31,
              backgroundColor: Colors.white,
              foregroundColor: _palette(context).primary,
              child: const Icon(Icons.pets_rounded, size: 31)),
          const SizedBox(width: 13),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('登录 Mfuns',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 20)),
                SizedBox(height: 5),
                Text('登录后查看你的动态与收藏',
                    style: TextStyle(color: Color(0xffe4e3ff))),
              ],
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.white, foregroundColor: _palette(context).primary),
            onPressed: onLogin,
            child: const Text('登录'),
          ),
        ],
      );
}

class _SignedInProfile extends StatelessWidget {
  const _SignedInProfile({
    required this.session,
    required this.controller,
    required this.themeSeed,
    required this.onThemeChanged,
  });

  final UserSession session;
  final AppController controller;
  final Color themeSeed;
  final ValueChanged<Color> onThemeChanged;

  void _openProfile(BuildContext context) {
    final userId = session.userId;
    if (userId == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) =>
            UserProfilePage(controller: controller, userId: userId)));
  }

  @override
  Widget build(BuildContext context) => Row(
        children: [
          GestureDetector(
            onTap: () => _openProfile(context),
            child: CircleAvatar(
              radius: 31,
              backgroundColor: Colors.white,
              foregroundColor: _palette(context).primary,
              foregroundImage: session.avatar.isEmpty
                  ? null
                  : NetworkImage(session.avatar),
              child: Text(
                  session.displayName.isEmpty
                      ? '?'
                      : session.displayName.substring(0, 1),
                  style: const TextStyle(
                      fontSize: 25, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(session.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 20)),
                const SizedBox(height: 5),
                Text(session.userId == null ? '欢迎回来' : 'UID ${session.userId}',
                    style: const TextStyle(color: Color(0xffe4e3ff))),
              ],
            ),
          ),
          IconButton(
            tooltip: '主题外观',
            onPressed: () => _showThemeSheet(context, themeSeed, onThemeChanged),
            icon: const Icon(Icons.palette_outlined, color: Colors.white),
          ),
        ],
      );
}

class _ThemeSheet extends StatefulWidget {
  const _ThemeSheet({required this.seed, required this.onSelected});

  final Color seed;
  final ValueChanged<Color> onSelected;

  @override
  State<_ThemeSheet> createState() => _ThemeSheetState();
}

class _ThemeSheetState extends State<_ThemeSheet> {
  late final TextEditingController _hex;

  static const swatches = <Color>[
    Color(0xFF5094B2), // 希露菲青（默认）
    Colors.indigo,
    Colors.blue,
    Colors.cyan,
    Colors.teal,
    Colors.green,
    Colors.lime,
    Colors.orange,
    Colors.deepOrange,
    Colors.pink,
    Colors.purple,
    Colors.brown,
    Colors.blueGrey,
  ];

  @override
  void initState() {
    super.initState();
    _hex = TextEditingController(text: _hexOf(widget.seed));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  static String _hexOf(Color color) {
    final value = color.value;
    return '#${(value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  Color? _parseHex(String input) {
    var value = input.trim().replaceFirst('#', '');
    if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(value)) {
      return Color(0xFF000000 | int.parse(value, radix: 16));
    }
    if (RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(value)) {
      return Color(int.parse(value, radix: 16));
    }
    return null;
  }

  void _applyCustom() {
    final color = _parseHex(_hex.text);
    if (color == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('色号格式不正确，请输入 #RRGGBB 或 RRGGBB')));
      return;
    }
    widget.onSelected(color);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    final seed = widget.seed;
    return _RaisedSheet(
      dragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.palette_rounded, color: palette.primary),
              const SizedBox(width: 8),
              const Text('主题颜色',
                  style: TextStyle(
                      color: _ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 14,
            children: swatches.map((color) {
              final selected = color.value == seed.value;
              return InkWell(
                key: ValueKey(color),
                customBorder: const CircleBorder(),
                onTap: () {
                  widget.onSelected(color);
                  Navigator.of(context).pop();
                },
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: selected
                        ? Border.all(color: _ink, width: 2.5)
                        : null,
                  ),
                  child: selected
                      ? const Icon(Icons.check_rounded,
                          color: Colors.white, size: 22)
                      : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          const Text('自定义色号',
              style: TextStyle(
                  color: _ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _parseHex(_hex.text) ?? const Color(0xFFCCCCCC),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0x22000000)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _hex,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    hintText: '#5094B2',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _applyCustom(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _applyCustom,
                child: const Text('应用'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text('选择后即生效',
              style: TextStyle(color: _muted, fontSize: 12)),
        ],
      ),
    );
  }
}

/// 底部弹层通用外框：默认高度为屏幕高度的 1/2；键盘弹出时整体上移至键盘上方并
/// 压缩到可用空间内，输入框与登录按钮始终不被遮挡；内容超出高度时允许滚动。
class _RaisedSheet extends StatelessWidget {
  const _RaisedSheet({required this.child, this.dragHandle = false});

  final Widget child;
  final bool dragHandle;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final viewInsets = media.viewInsets.bottom;
    final availableHeight = media.size.height - viewInsets;
    final height = (media.size.height / 2).clamp(0.0, availableHeight);
    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: viewInsets),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          height: height,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 26),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dragHandle) ...[
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xffdedde7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _showThemeSheet(
    BuildContext context, Color seed, ValueChanged<Color> onChanged) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ThemeSheet(seed: seed, onSelected: onChanged),
  );
}

class _ProfileGuestBody extends StatelessWidget {
  const _ProfileGuestBody({
    required this.controller,
    required this.themeSeed,
    required this.onThemeChanged,
  });

  final AppController controller;
  final Color themeSeed;
  final ValueChanged<Color> onThemeChanged;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          const _ProfileItem(
              icon: Icons.history_rounded,
              title: '历史记录',
              subtitle: '登录后同步浏览记录'),
          const SizedBox(height: 10),
          const _ProfileItem(
              icon: Icons.bookmark_outline_rounded,
              title: '我的收藏',
              subtitle: '把喜欢的内容留在这里'),
          const SizedBox(height: 10),
          _ProfileItem(
            icon: Icons.palette_outlined,
            title: '主题外观',
            subtitle: '自定义界面主题颜色',
            onTap: () => _showThemeSheet(context, themeSeed, onThemeChanged),
          ),
          const SizedBox(height: 10),
          _ProfileItem(
            icon: Icons.settings_outlined,
            title: '设置',
            subtitle: '编辑资料、清除缓存与关于',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => SettingsPage(controller: controller))),
          ),
        ],
      );
}

class _ProfileMemberBody extends StatelessWidget {
  const _ProfileMemberBody({
    required this.controller,
    required this.themeSeed,
    required this.onThemeChanged,
  });

  final AppController controller;
  final Color themeSeed;
  final ValueChanged<Color> onThemeChanged;

  Future<void> _confirmLogout(BuildContext context, AppController controller) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: const Text('退出当前账号'),
        content: const Text('退出后将清除登录凭证，需要重新登录才能继续使用。确定退出吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await controller.clearLocalSession();
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          _LevelProgressCard(
            session: controller.session,
            sections: controller.levelSections,
          ),
          const SizedBox(height: 12),
          _MemberStats(controller: controller),
          const SizedBox(height: 18),
          const _ProfileSectionTitle('创作与账号'),
          _ProfileItem(
            icon: Icons.edit_note_rounded,
            title: '我的投稿',
            subtitle: '发布、编辑和管理投稿',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) =>
                    SubmissionsPage(controller: controller)))),
          const SizedBox(height: 10),
          _ProfileItem(
            icon: Icons.calendar_month_rounded,
            title: '每日签到',
            subtitle: '签到领经验，查看今日签到排行',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => SignPage(controller: controller)))),
          const SizedBox(height: 10),
          _ProfileItem(
            icon: Icons.account_balance_wallet_outlined,
            title: '我的资产',
            subtitle: '喵币余额、改名卡与补签卡',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => AssetsPage(controller: controller)))),
          const SizedBox(height: 10),
          _ProfileItem(
            icon: Icons.palette_outlined,
            title: '主题外观',
            subtitle: '自定义界面主题颜色',
            onTap: () => _showThemeSheet(context, themeSeed, onThemeChanged),
          ),
          const SizedBox(height: 10),
          _ProfileItem(
            icon: Icons.settings_outlined,
            title: '设置',
            subtitle: '编辑资料、清除缓存与关于',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => SettingsPage(controller: controller))),
          ),
          const SizedBox(height: 10),
          _ProfileItem(
            icon: Icons.logout_rounded,
            title: '退出当前会话',
            subtitle: '这将清除登录凭证',
            onTap: () => _confirmLogout(context, controller),
          ),
        ],
      );
}

/// 等级 ID → 段位（1=D, 2=D+, 3=C, 4=C+, 5=B, 6=B+, 7=A, 8=A+, 9=S, 10=S+）。
String _levelRankLabel(int? levelId) {
  const ranks = ['D', 'D+', 'C', 'C+', 'B', 'B+', 'A', 'A+', 'S', 'S+'];
  if (levelId == null || levelId < 1 || levelId > ranks.length) {
    return levelId == null ? '' : 'Lv.$levelId';
  }
  return ranks[levelId - 1];
}

Color _levelRankColor(int? levelId) => switch (_levelRankLabel(levelId)) {
      'S' || 'S+' => const Color(0xFFE6A23C),
      'A' || 'A+' => const Color(0xFFE04F4F),
      'B' || 'B+' => const Color(0xFF4F7FE0),
      'C' || 'C+' => const Color(0xFF4FA36C),
      _ => const Color(0xFF8A9096),
    };

class _LevelProgressCard extends StatelessWidget {
  const _LevelProgressCard({required this.session, required this.sections});

  final UserSession? session;
  final List<LevelSection> sections;

  @override
  Widget build(BuildContext context) {
    final levelId = session?.levelId;
    final exp = session?.exp;
    if (levelId == null && exp == null) return const SizedBox.shrink();
    final label = _levelRankLabel(levelId);
    final color = _levelRankColor(levelId);

    // 计算当前等级区间与下一级所需经验，用于进度条。
    var progress = 0.0;
    String? hint;
    if (levelId != null && exp != null && sections.length >= levelId) {
      final current = sections[levelId - 1].experience;
      final next = levelId < sections.length
          ? sections[levelId].experience
          : null;
      if (next != null && next > current) {
        progress = ((exp - current) / (next - current)).clamp(0.0, 1.0);
        final remaining = next - exp;
        hint = '距 ${_levelRankLabel(levelId + 1)} 还差 $remaining 经验';
      } else {
        progress = 1;
        hint = '已达最高等级';
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withOpacity(.12),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: color.withOpacity(.55)),
                  ),
                  child: Text(
                    label.isEmpty ? '等级' : '等级 $label',
                    style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .4),
                  ),
                ),
                const Spacer(),
                if (exp != null)
                  Text('经验 $exp',
                      style: const TextStyle(color: _muted, fontSize: 12.5)),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: color.withOpacity(.12),
                color: color,
              ),
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                if (hint != null)
                  Expanded(
                    child: Text(hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: _muted, fontSize: 11.5)),
                  ),
                if (levelId != null)
                  Text('Lv.$levelId',
                      style: const TextStyle(color: _muted, fontSize: 11.5)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberStats extends StatelessWidget {
  const _MemberStats({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              _MemberStat(
                label: '历史',
                value: '${controller.history.length}',
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => _HistoryPage(controller: controller))),
              ),
              const _StatDivider(),
              _MemberStat(
                label: '收藏夹',
                value: '${controller.favoriteFolders.length}',
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) =>
                        _FavoriteFoldersPage(controller: controller))),
              ),
              const _StatDivider(),
              _MemberStat(
                label: '投稿',
                value: '${controller.submissionTotal}',
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => SubmissionsPage(controller: controller))),
              ),
            ],
          ),
        ),
      );
}

class _MemberStat extends StatelessWidget {
  const _MemberStat({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          child: Column(
            children: [
              Text(value,
                  style: const TextStyle(
                      color: _ink, fontWeight: FontWeight.w900, fontSize: 18)),
              const SizedBox(height: 3),
              Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
            ],
          ),
        ),
      );
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 29, color: const Color(0xffecebf2));
}

class _ProfileSectionTitle extends StatelessWidget {
  const _ProfileSectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(text,
              style: const TextStyle(
                  color: _muted, fontSize: 13, fontWeight: FontWeight.w700)),
        ),
      );
}

class _ProfileItem extends StatelessWidget {
  const _ProfileItem(
      {required this.icon,
      required this.title,
      required this.subtitle,
      this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: onTap,
          leading: CircleAvatar(
            backgroundColor:
                _palette(context).primary.withOpacity(.11),
            foregroundColor: _palette(context).primary,
            child: Icon(icon),
          ),
          title: Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _ink)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
      );
}

class _HistoryPage extends StatefulWidget {
  const _HistoryPage({required this.controller});

  final AppController controller;

  @override
  State<_HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<_HistoryPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.loadHistory();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('历史记录'), centerTitle: true),
        body: _PatternBackground(
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) => RefreshIndicator(
              color: _palette(context).accent,
              onRefresh: widget.controller.loadHistory,
              child: _ContentGrid(
                controller: widget.controller,
                items: widget.controller.history,
                isLoading: widget.controller.isLoadingHistory,
                error: widget.controller.historyError,
                emptyText: '还没有浏览记录',
                onLoadMore: widget.controller.loadMoreHistory,
                isLoadingMore: widget.controller.isLoadingMoreHistory,
                hasMore: widget.controller.hasMoreHistory,
              ),
            ),
          ),
        ),
      );
}

class _FavoriteFoldersPage extends StatefulWidget {
  const _FavoriteFoldersPage({required this.controller});

  final AppController controller;

  @override
  State<_FavoriteFoldersPage> createState() => _FavoriteFoldersPageState();
}

class _FavoriteFoldersPageState extends State<_FavoriteFoldersPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.loadFavoriteFolders();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('我的收藏'), centerTitle: true),
        body: _PatternBackground(
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              final folders = widget.controller.favoriteFolders;
              if (widget.controller.isLoadingFavorites && folders.isEmpty) {
                return const _LoadingState();
              }
              if (widget.controller.favoritesError != null && folders.isEmpty) {
                return _MessageState(
                    message: widget.controller.favoritesError!);
              }
              if (folders.isEmpty) {
                return const _MessageState(message: '还没有收藏夹');
              }
              return RefreshIndicator(
                color: _palette(context).accent,
                onRefresh: widget.controller.loadFavoriteFolders,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  itemCount: folders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final folder = folders[index];
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: CircleAvatar(
                          backgroundColor: _palette(context).primary.withOpacity(.13),
                          foregroundColor: _palette(context).primary,
                          child: const Icon(Icons.bookmark_rounded),
                        ),
                        title: Text(folder.name,
                            style: const TextStyle(
                                color: _ink, fontWeight: FontWeight.w700)),
                        subtitle: Text(folder.description.isEmpty
                            ? '${folder.count} 个内容'
                            : folder.description),
                        trailing: Text('${folder.count}',
                            style: const TextStyle(
                                color: _muted, fontWeight: FontWeight.w700)),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => _FavoriteItemsPage(
                              controller: widget.controller,
                              folder: folder,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      );
}

class _FavoriteItemsPage extends StatefulWidget {
  const _FavoriteItemsPage({required this.controller, required this.folder});

  final AppController controller;
  final FavoriteFolder folder;

  @override
  State<_FavoriteItemsPage> createState() => _FavoriteItemsPageState();
}

class _FavoriteItemsPageState extends State<_FavoriteItemsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.loadFavoriteItems(widget.folder.id);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.folder.name), centerTitle: true),
        body: _PatternBackground(
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) => RefreshIndicator(
              color: _palette(context).accent,
              onRefresh: () =>
                  widget.controller.loadFavoriteItems(widget.folder.id),
              child: _ContentGrid(
                controller: widget.controller,
                items: widget.controller.favoriteItems,
                isLoading: widget.controller.isLoadingFavorites,
                error: widget.controller.favoritesError,
                emptyText: '收藏夹里还没有内容',
                onLoadMore: () => widget.controller
                    .loadFavoriteItems(widget.folder.id, loadMore: true),
                isLoadingMore: widget.controller.isLoadingMoreFavorites,
                hasMore: widget.controller.hasMoreFavoriteItems,
              ),
            ),
          ),
        ),
      );
}

class _ContentGrid extends StatelessWidget {
  const _ContentGrid({
    required this.controller,
    required this.items,
    required this.isLoading,
    required this.error,
    required this.emptyText,
    this.onLoadMore,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.scrollController,
    this.junctionIndex,
    this.onJunctionTap,
  });

  final AppController controller;
  final List<ContentPreview> items;
  final bool isLoading;
  final String? error;
  final String emptyText;
  final Future<void> Function()? onLoadMore;
  final bool isLoadingMore;
  final bool hasMore;
  final ScrollController? scrollController;

  /// 新内容交界位置：在此处插入“刚刚看到这里”标记（行首全宽）。
  final int? junctionIndex;
  final VoidCallback? onJunctionTap;

  @override
  Widget build(BuildContext context) {
    if (isLoading && items.isEmpty) return const _LoadingState();
    if (error != null && items.isEmpty) return _MessageState(message: error!);
    if (items.isEmpty) return _MessageState(message: emptyText);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 卡片高度由内容决定：封面 + 两行标题 + 作者 + 数据行 + 内边距，
        // 而不是用固定宽高比把空白硬塞进卡片（标题下方会出现大段空白）。
        final isLandscape =
            MediaQuery.orientationOf(context) == Orientation.landscape;
        final columns = isLandscape ? 4 : 2;
        final cardWidth =
            (constraints.maxWidth - 24 - (columns - 1) * 10) / columns;
        final cellHeight = cardWidth / 1.38 + 96;
        final delegate = SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 12,
          crossAxisSpacing: 10,
          mainAxisExtent: cellHeight,
        );
        final junction = (junctionIndex ?? 0).clamp(0, items.length);
        Widget footer;
        if (isLoadingMore) {
          footer = const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
          );
        } else if (!hasMore && onLoadMore != null) {
          footer = const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Center(
                child: Text('已经到底了',
                    style: TextStyle(color: _muted, fontSize: 12))),
          );
        } else {
          footer = const SizedBox(height: 2);
        }
        final slivers = <Widget>[
          if (junction > 0) ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              sliver: SliverGrid(
                gridDelegate: delegate,
                delegate: SliverChildBuilderDelegate(
                  (context, index) =>
                      _ContentCard(controller: controller, item: items[index]),
                  childCount: junction,
                ),
              ),
            ),
            // 新内容与旧内容的交界标记：点击刷新并回到顶部。
            SliverToBoxAdapter(child: _FeedJunction(onTap: onJunctionTap)),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
          ],
          SliverPadding(
            padding: EdgeInsets.fromLTRB(12, junction > 0 ? 0 : 12, 12, 82),
            sliver: SliverGrid(
              gridDelegate: delegate,
              delegate: SliverChildBuilderDelegate(
                (context, index) => _ContentCard(
                    controller: controller, item: items[junction + index]),
                childCount: items.length - junction,
              ),
            ),
          ),
          if (onLoadMore != null) SliverToBoxAdapter(child: footer),
        ];
        final scroll = CustomScrollView(
          controller: scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: slivers,
        );
        if (onLoadMore == null) return scroll;
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.extentAfter < 300 &&
                hasMore &&
                !isLoadingMore) {
              onLoadMore!();
            }
            return false;
          },
          child: scroll,
        );
      },
    );
  }
}

/// 信息流交界标记：刷新后新内容插入在旧内容之上，
/// 在交界处提示“刚刚看到这里”，点击刷新并回到顶部查看新内容。
class _FeedJunction extends StatelessWidget {
  const _FeedJunction({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xffeeedf5),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0x33888888)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh_rounded, size: 15, color: _muted),
                  SizedBox(width: 6),
                  Text('刚刚看到这里，点击刷新',
                      style: TextStyle(color: _muted, fontSize: 12.5)),
                ],
              ),
            ),
          ),
        ),
      );
}

class _ContentCard extends StatelessWidget {
  const _ContentCard({required this.controller, required this.item});

  final AppController controller;
  final ContentPreview item;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (_) =>
                    ContentDetailPage(controller: controller, preview: item)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1.38,
                child: _CoverImage(item: item),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(9, 8, 9, 3),
                child: Text(item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: _ink,
                        fontSize: 13.5,
                        height: 1.25,
                        fontWeight: FontWeight.w600)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9),
                child: Text(item.author.isEmpty ? 'Mfuns 用户' : item.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 11.5)),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(9, 3, 9, 8),
                child: Row(
                  children: [
                    const Icon(Icons.favorite_rounded,
                        size: 13, color: _muted),
                    const SizedBox(width: 3),
                    Text('${item.likes}',
                        style: const TextStyle(color: _muted, fontSize: 11)),
                    const SizedBox(width: 9),
                    const Icon(Icons.visibility_outlined,
                        size: 14, color: _muted),
                    const SizedBox(width: 3),
                    Expanded(
                        child: Text('${item.views}',
                            style: const TextStyle(color: _muted, fontSize: 11),
                            overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.item});

  final ContentPreview item;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          if (item.cover.isNotEmpty)
            Image.network(item.cover,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _CoverFallback(item: item))
          else
            _CoverFallback(item: item),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withOpacity(.55)],
              ),
            ),
          ),
          Positioned(
            left: 7,
            bottom: 6,
            child: Row(
              children: [
                Icon(
                    item.isVideo
                        ? Icons.play_circle_fill_rounded
                        : Icons.article_rounded,
                    color: Colors.white,
                    size: 17),
                const SizedBox(width: 4),
                Text(item.isVideo ? '视频' : '文章',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          if (item.category.isNotEmpty)
            Positioned(
              top: 7,
              right: 7,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                    color: Colors.black.withOpacity(.48),
                    borderRadius: BorderRadius.circular(5)),
                child: Text(item.category,
                    style: const TextStyle(color: Colors.white, fontSize: 10)),
              ),
            ),
        ],
      );
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback({required this.item});

  final ContentPreview item;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: item.isVideo
                ? const [Color(0xff625ed7), Color(0xffa77de9)]
                : const [Color(0xff5e90dd), Color(0xff95b3e6)],
          ),
        ),
        child: Center(
            child: Icon(
                item.isVideo
                    ? Icons.play_arrow_rounded
                    : Icons.article_outlined,
                color: Colors.white.withOpacity(.8),
                size: 46)),
      );
}

class _RankingList extends StatelessWidget {
  const _RankingList(
      {required this.controller,
      required this.items,
      required this.loading,
      required this.error});

  final AppController controller;
  final List<ContentPreview> items;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    if (loading && items.isEmpty) return const _LoadingState();
    if (error != null && items.isEmpty) return _MessageState(message: error!);
    final ranked = [...items]..sort((a, b) => b.views.compareTo(a.views));
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 82),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: ranked.length,
      separatorBuilder: (_, __) => const SizedBox(height: 9),
      itemBuilder: (context, index) => _RankingCard(
          controller: controller, item: ranked[index], rank: index + 1),
    );
  }
}

class _RankingCard extends StatelessWidget {
  const _RankingCard(
      {required this.controller, required this.item, required this.rank});

  final AppController controller;
  final ContentPreview item;
  final int rank;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) =>
                  ContentDetailPage(controller: controller, preview: item))),
          child: SizedBox(
            height: 91,
            child: Row(
              children: [
                SizedBox(
                  width: 39,
                  child: Center(
                      child: Text('$rank',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: rank <= 3 ? _palette(context).accent : _muted))),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: SizedBox(
                      width: 107, height: 68, child: _CoverImage(item: item)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding:
                        const EdgeInsets.only(right: 10, top: 11, bottom: 11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: _ink, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Text(
                            '${item.likes} 赞 · ${item.comments} 评论 · ${item.views} 浏览',
                            style:
                                const TextStyle(color: _muted, fontSize: 11.5)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) => Center(
      child: CircularProgressIndicator(color: _palette(context).primary));
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted)),
        ),
      );
}

class _PatternBackground extends StatelessWidget {
  const _PatternBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _DiamondPatternPainter(),
        child: child,
      );
}

class _DiamondPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xffececf3)
      ..strokeWidth = .7
      ..style = PaintingStyle.stroke;
    const step = 22.0;
    for (var x = -size.height; x < size.width; x += step) {
      canvas.drawLine(
          Offset(x, 0), Offset(x + size.height, size.height), paint);
      canvas.drawLine(
          Offset(x, size.height), Offset(x + size.height, 0), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Future<void> _showLoginSheet(BuildContext context, AppController controller) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _LoginSheet(controller: controller),
    );

class _LoginSheet extends StatefulWidget {
  const _LoginSheet({required this.controller});

  final AppController controller;

  @override
  State<_LoginSheet> createState() => _LoginSheetState();
}

class _LoginSheetState extends State<_LoginSheet> {
  final _account = TextEditingController();
  final _password = TextEditingController();
  var _obscurePassword = true;

  @override
  void dispose() {
    _account.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_account.text.trim().isEmpty || _password.text.isEmpty) return;
    final error = await widget.controller.login(_account.text, _password.text);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  @override
  Widget build(BuildContext context) => _RaisedSheet(
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  CircleAvatar(
                      backgroundColor: const Color(0xffefefff),
                      foregroundColor: _palette(context).primary,
                      child: const Icon(Icons.pets_rounded)),
                  const SizedBox(width: 10),
                  const Text('登录 Mfuns',
                      style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          color: _ink)),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _account,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.username],
                decoration:
                    const InputDecoration(labelText: '用户名 / ID / 邮箱 / 手机号'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: _obscurePassword,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _login(),
                decoration: InputDecoration(
                  labelText: '密码',
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                    icon: Icon(_obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: _palette(context).primary,
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: widget.controller.isLoggingIn ? null : _login,
                  child: widget.controller.isLoggingIn
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('登录'),
                ),
              ),
            ],
          ),
        ),
      );
}
