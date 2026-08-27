import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/config/user_preferences.dart';
import '../core/network/mfuns_api_client.dart';
import '../core/notify/local_message_notifier.dart';
import '../features/auth/auth_repository.dart';
import '../features/auth/session_store.dart';
import '../features/home/home_repository.dart';
import '../features/latest/latest_mfuns_repository.dart';

class AppController extends ChangeNotifier {
  AppController({SessionStore? sessionStore})
      : _api = MfunsApiClient(),
        _sessionStore = sessionStore ?? SessionStore(),
        _recommendations = const [],
        _searchResults = const [],
        _hotRankings = const [],
        _categories = const [],
        _categoryContents = const [],
        _feeds = const [],
        _followingFeeds = const [],
        _latestItems = const [],
        _history = const [],
        _favoriteFolders = const [],
        _favoriteItems = const [] {
    _auth = AuthRepository(_api);
    _home = HomeRepository(_api);
    _latest = LatestMfunsRepository();
  }

  final MfunsApiClient _api;
  final SessionStore _sessionStore;
  late final AuthRepository _auth;

  /// 通知点击等场景请求主界面切换到指定底部标签（0 首页 / 1 动态 / 2 消息 / 3 我的）。
  final ValueNotifier<int> homeTabRequest = ValueNotifier<int>(0);

  /// 消息中心子标签请求：0 私信 / 1 通知。
  final ValueNotifier<int> messageSubTabRequest = ValueNotifier<int>(0);

  /// 通知页子标签请求：0 赞 / 1 评论 / 2 提及。
  final ValueNotifier<int> notifySubTabRequest = ValueNotifier<int>(0);

  /// 请求切换到消息中心对应页面（通知点击跳转用）。
  /// [subTab] 0 私信 / 1 通知；[notifyTab] 通知页子标签 0 赞 / 1 评论 / 2 提及。
  void openMessagesTab({int subTab = 0, int? notifyTab}) {
    homeTabRequest.value = 2;
    messageSubTabRequest.value = subTab;
    if (notifyTab != null) {
      notifySubTabRequest.value = notifyTab;
      _notifyTabConsumed = false;
    }
    refreshUnreadCounts();
  }

  bool _notifyTabConsumed = true;

  /// 通知页晚于跳转请求构建时，消费未应用的子标签跳转（只生效一次）。
  bool consumeNotifySubTab() {
    if (_notifyTabConsumed) return false;
    _notifyTabConsumed = true;
    return true;
  }
  late final HomeRepository _home;
  late final LatestMfunsRepository _latest;

  List<ContentPreview> _recommendations;
  List<ContentPreview> _searchResults;
  List<UserProfile> _searchUserResults = const [];
  List<ContentPreview> _hotRankings;
  List<CategoryNode> _categories;
  List<ContentPreview> _categoryContents;
  List<TimelineFeed> _feeds;
  List<TimelineFeed> _followingFeeds;
  List<LatestMfunsItem> _latestItems;

  /// 本次会话中用户标记过的资源 stableId 集合。
  /// 刷新后仍在本地过滤这些资源，避免被标记（折叠）的内容重新出现。
  final Set<String> _latestMarkedIds = <String>{};
  List<ContentPreview> _history;
  List<FavoriteFolder> _favoriteFolders;
  List<ContentPreview> _favoriteItems;
  int _favoriteItemsLastId = 0;
  bool _hasMoreFavoriteItems = true;
  bool _isLoadingMoreFavorites = false;
  int _submissionTotal = 0;
  UserSession? _session;
  Timer? _unreadTimer;
  int _unreadCount = 0;
  int _notifyUnread = 0;
  NotifyCounts? _lastNotifyCounts;
  String? _homeError;
  String? _searchError;
  String? _searchUserError;
  String? _hotRankingsError;
  String? _categoriesError;
  String? _categoryContentsError;
  String? _feedsError;
  String? _followingFeedsError;
  String? _latestItemsError;
  String? _historyError;
  String? _favoritesError;
  bool _isLoadingHome = false;
  bool _isSearching = false;
  bool _isSearchingUser = false;
  bool _isLoggingIn = false;
  bool _isRestoringSession = false;
  bool _isLoadingHotRankings = false;
  bool _isLoadingCategories = false;
  bool _isLoadingCategoryContents = false;
  bool _isLoadingFeeds = false;
  bool _isLoadingMoreFeeds = false;
  bool _isLoadingFollowingFeeds = false;
  bool _isLoadingMoreFollowingFeeds = false;
  bool _hasMoreFeeds = true;
  bool _hasMoreFollowingFeeds = true;
  bool _isLoadingLatestItems = false;
  bool _isLoadingMoreLatestItems = false;
  bool _hasMoreLatestItems = true;
  double? _latestBefore;
  int _timelinePage = 1;
  bool _isLoadingHistory = false;
  bool _isLoadingFavorites = false;
  SignInfo? _signInfo;
  List<SignRankEntry> _signRank = const [];
  Map<int, List<SignAward>> _signAwards = const {};
  bool _isSigning = false;
  bool _isLoadingSignInfo = false;
  bool _isLoadingSignRank = false;
  String? _signInfoError;
  String? _signRankError;
  List<LevelSection> _levelSections = const [];
  bool _isLoadingLevelSections = false;
  bool _autoSignIn = false;
  Timer? _autoSignTimer;
  int _autoSignAttemptedDay = 0;

  List<ContentPreview> get recommendations => _recommendations;
  List<ContentPreview> get searchResults => _searchResults;
  List<UserProfile> get searchUserResults => _searchUserResults;
  List<ContentPreview> get hotRankings => _hotRankings;
  List<CategoryNode> get categories => _categories;
  List<ContentPreview> get categoryContents => _categoryContents;
  List<TimelineFeed> get feeds => _feeds;
  List<TimelineFeed> get followingFeeds => _followingFeeds;
  List<LatestMfunsItem> get latestItems => _latestItems;
  List<ContentPreview> get history => _history;
  List<FavoriteFolder> get favoriteFolders => _favoriteFolders;
  List<ContentPreview> get favoriteItems => _favoriteItems;
  bool get isLoadingMoreFavorites => _isLoadingMoreFavorites;
  bool get hasMoreFavoriteItems => _hasMoreFavoriteItems;
  int get submissionTotal => _submissionTotal;
  UserSession? get session => _session;
  String? get homeError => _homeError;
  String? get searchError => _searchError;
  String? get searchUserError => _searchUserError;
  String? get hotRankingsError => _hotRankingsError;
  String? get categoriesError => _categoriesError;
  String? get categoryContentsError => _categoryContentsError;
  String? get feedsError => _feedsError;
  String? get followingFeedsError => _followingFeedsError;
  String? get latestItemsError => _latestItemsError;
  String? get historyError => _historyError;
  String? get favoritesError => _favoritesError;
  bool get isLoadingHome => _isLoadingHome;
  bool get isSearching => _isSearching;
  bool get isSearchingUser => _isSearchingUser;
  bool get isLoggingIn => _isLoggingIn;
  bool get isRestoringSession => _isRestoringSession;
  bool get isLoadingHotRankings => _isLoadingHotRankings;
  bool get isLoadingCategories => _isLoadingCategories;
  bool get isLoadingCategoryContents => _isLoadingCategoryContents;
  bool get isLoadingFeeds => _isLoadingFeeds;
  bool get isLoadingMoreFeeds => _isLoadingMoreFeeds;
  bool get isLoadingFollowingFeeds => _isLoadingFollowingFeeds;
  bool get isLoadingMoreFollowingFeeds => _isLoadingMoreFollowingFeeds;
  bool get hasMoreFeeds => _hasMoreFeeds;
  bool get hasMoreFollowingFeeds => _hasMoreFollowingFeeds;
  bool get isLoadingLatestItems => _isLoadingLatestItems;
  bool get isLoadingMoreLatestItems => _isLoadingMoreLatestItems;
  bool get hasMoreLatestItems => _hasMoreLatestItems;
  bool get isLoadingHistory => _isLoadingHistory;
  bool get isLoadingFavorites => _isLoadingFavorites;
  bool get hasMoreHistory => _hasMoreHistory;
  bool get isLoadingMoreHistory => _isLoadingMoreHistory;
  List<BackpackItem> get backpack => _backpack;
  bool get isLoadingBackpack => _isLoadingBackpack;
  String? get backpackError => _backpackError;
  SignInfo? get signInfo => _signInfo;
  List<SignRankEntry> get signRank => _signRank;
  Map<int, List<SignAward>> get signAwards => _signAwards;
  bool get isSigning => _isSigning;
  bool get isLoadingSignInfo => _isLoadingSignInfo;
  bool get isLoadingSignRank => _isLoadingSignRank;
  String? get signInfoError => _signInfoError;
  String? get signRankError => _signRankError;
  List<LevelSection> get levelSections => _levelSections;
  bool get isLoadingLevelSections => _isLoadingLevelSections;
  bool get autoSignIn => _autoSignIn;

  Future<void> initialize() async {
    _isRestoringSession = true;
    notifyListeners();
    try {
      final token = await _sessionStore.readToken();
      if (token != null && token.isNotEmpty) {
        _session = await _auth.restore(token);
        if (_session == null) await _sessionStore.clear();
      }
    } catch (_) {
      // Storage availability must not block public content browsing.
    } finally {
      _isRestoringSession = false;
      notifyListeners();
    }
    await Future.wait([refreshHome(), loadCategories(), loadLevelSections()]);
    if (_session != null) _startUnreadPolling();
    await _initAutoSign();
  }

  /// 开启自动签到：应用打开状态下每天零点尝试签到。
  /// 启动时加载偏好并启动周期检查；不配置自启动权限。
  Future<void> _initAutoSign() async {
    _autoSignIn = await UserPreferences.loadAutoSignIn();
    _autoSignTimer?.cancel();
    if (!_autoSignIn) return;
    _autoSignTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _maybeAutoSign();
    });
    _maybeAutoSign();
  }

  /// 设置自动签到开关并持久化。
  Future<void> setAutoSignIn(bool enabled) async {
    if (_autoSignIn == enabled) return;
    _autoSignIn = enabled;
    await UserPreferences.saveAutoSignIn(enabled);
    _autoSignTimer?.cancel();
    if (enabled) {
      _autoSignTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _maybeAutoSign();
      });
      _maybeAutoSign();
    }
    notifyListeners();
  }

  /// 自动签到：应用启动时（以及运行期间每天零点后）检查今日签到状态，
  /// 若未签到则自动完成签到；每天最多成功一次。
  Future<void> _maybeAutoSign() async {
    if (!_autoSignIn || _session == null) return;
    final now = DateTime.now();
    if (_autoSignAttemptedDay == now.day) return;
    _autoSignAttemptedDay = now.day;
    try {
      // 先查今日是否已签到，避免重复签到报错。
      final info = await _home.signList();
      if (info.signedDays.contains(now.day)) return;
      await sign();
    } catch (_) {
      // 网络/接口失败时重置标记，允许下一次周期检查重试。
      _autoSignAttemptedDay = 0;
    }
  }

  /// 加载等级经验区间表（公开接口，通常只加载一次）。
  Future<void> loadLevelSections() async {
    if (_isLoadingLevelSections || _levelSections.isNotEmpty) return;
    _isLoadingLevelSections = true;
    notifyListeners();
    try {
      _levelSections = await _home.getLevelSections();
    } on MfunsApiException {
      // 等级进度条缺失时保持可用的简化展示。
    } finally {
      _isLoadingLevelSections = false;
      notifyListeners();
    }
  }

  /// 刷新首页推荐：新内容前置合并，返回本次新增条数（用于交界标记）。
  Future<int> refreshHome() async {
    _isLoadingHome = true;
    _homeError = null;
    notifyListeners();
    try {
      final fresh = await _home.getRecommendations();
      final existingIds =
          _recommendations.map((i) => '${i.type}:${i.id}').toSet();
      final added = fresh
          .where((item) =>
              item.id != 0 && !existingIds.contains('${item.type}:${item.id}'))
          .length;
      _recommendations = mergeRecommendations(fresh, _recommendations);
      return added;
    } on MfunsApiException catch (error) {
      _homeError = error.message;
      return 0;
    } finally {
      _isLoadingHome = false;
      notifyListeners();
    }
  }

  /// 首页推荐保留的最大条数：刷新会累计追加新推荐，超过上限后丢弃最旧的。
  static const int maxRecommendations = 100;

  /// 把新一批推荐合并到现有列表：新内容在前、按（类型, id）去重，
  /// 超过 [maxRecommendations] 后截断最旧的条目。
  static List<ContentPreview> mergeRecommendations(
    List<ContentPreview> fresh,
    List<ContentPreview> existing,
  ) {
    final seen = <String>{};
    final merged = <ContentPreview>[];
    for (final item in [...fresh, ...existing]) {
      if (item.id != 0 && !seen.add('${item.type}:${item.id}')) continue;
      merged.add(item);
    }
    return merged.length > maxRecommendations
        ? merged.sublist(0, maxRecommendations)
        : merged;
  }

  /// 每日签到（需登录）；成功后刷新签到信息，返回服务端提示消息。
  Future<String> sign() async {
    if (_isSigning) return '';
    _isSigning = true;
    notifyListeners();
    try {
      final message = await _home.sign();
      await loadSignInfo();
      return message;
    } finally {
      _isSigning = false;
      notifyListeners();
    }
  }

  Future<void> loadSignInfo() async {
    _isLoadingSignInfo = true;
    _signInfoError = null;
    notifyListeners();
    try {
      _signInfo = await _home.signList();
    } on MfunsApiException catch (error) {
      _signInfoError = error.message;
    } finally {
      _isLoadingSignInfo = false;
      notifyListeners();
    }
  }

  /// 补签指定日期（需登录，消耗补签卡）；成功后刷新签到信息。
  Future<void> signAgain(int day) async {
    await _home.signAgain(day);
    await loadSignInfo();
  }

  Future<void> loadSignRank() async {
    _isLoadingSignRank = true;
    _signRankError = null;
    notifyListeners();
    try {
      _signRank = await _home.signRankToday();
    } on MfunsApiException catch (error) {
      _signRankError = error.message;
    } finally {
      _isLoadingSignRank = false;
      notifyListeners();
    }
  }

  Future<void> loadSignAwards() async {
    try {
      _signAwards = await _home.accumulatedAwards();
      notifyListeners();
    } on MfunsApiException {
      // 奖励表加载失败不影响签到主流程。
    }
  }

  Future<void> search(String text, {int type = -1}) async {
    final query = text.trim();
    if (query.isEmpty) {
      _searchResults = const [];
      _searchError = null;
      notifyListeners();
      return;
    }
    _isSearching = true;
    _searchError = null;
    notifyListeners();
    try {
      _searchResults = await _home.search(query, type: type);
    } on MfunsApiException catch (error) {
      _searchError = error.message;
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  /// 搜索用户（搜索页「用户」标签）：状态存于 [searchUserResults]。
  Future<void> searchUser(String text) async {
    final query = text.trim();
    if (query.isEmpty) {
      _searchUserResults = const [];
      _searchUserError = null;
      notifyListeners();
      return;
    }
    _isSearchingUser = true;
    _searchUserError = null;
    notifyListeners();
    try {
      _searchUserResults = await _home.searchUsers(query);
    } on MfunsApiException catch (error) {
      _searchUserError = error.message;
    } finally {
      _isSearchingUser = false;
      notifyListeners();
    }
  }

  Future<void> loadHotRankings() async {
    _isLoadingHotRankings = true;
    _hotRankingsError = null;
    notifyListeners();
    try {
      _hotRankings = await _home.getHotRankings();
    } on MfunsApiException catch (error) {
      _hotRankingsError = error.message;
    } finally {
      _isLoadingHotRankings = false;
      notifyListeners();
    }
  }

  Future<void> loadCategories() async {
    _isLoadingCategories = true;
    _categoriesError = null;
    notifyListeners();
    try {
      _categories = await _home.getCategories();
    } on MfunsApiException catch (error) {
      _categoriesError = error.message;
    } finally {
      _isLoadingCategories = false;
      notifyListeners();
    }
  }

  /// 当前 [categoryContents] 所属的分区 id；null 表示尚未加载。
  int? _categoryContentsFor;

  Future<void> loadCategoryContents(int categoryId) async {
    _isLoadingCategoryContents = true;
    _categoryContentsError = null;
    notifyListeners();
    try {
      final fresh = await _home.getCategoryContents(categoryId);
      // 切换分区时整体替换；刷新同一分区时累计追加（去重、上限 100）。
      if (_categoryContentsFor != categoryId) {
        _categoryContents = fresh;
        _categoryContentsFor = categoryId;
      } else {
        _categoryContents = mergeRecommendations(fresh, _categoryContents);
      }
    } on MfunsApiException catch (error) {
      _categoryContentsError = error.message;
    } finally {
      _isLoadingCategoryContents = false;
      notifyListeners();
    }
  }

  Future<void> loadFeeds() async {
    await _refreshTimeline(following: false);
  }

  Future<void> loadMoreFeeds() => _loadMoreTimeline(following: false);

  Future<void> loadFollowingFeeds() async {
    if (_session == null) {
      _followingFeeds = const [];
      _followingFeedsError = null;
      _hasMoreFollowingFeeds = false;
      notifyListeners();
      return;
    }
    await _refreshTimeline(following: true);
  }

  Future<void> loadMoreFollowingFeeds() => _loadMoreTimeline(following: true);

  /// 过滤掉本次会话中已被用户标记的资源（本地记住，刷新后不再出现）。
  List<LatestMfunsItem> _filterLatestMarked(List<LatestMfunsItem> items) =>
      items
          .where((item) => !_latestMarkedIds.contains(item.stableId))
          .toList(growable: false);

  Future<void> loadLatestItems() async {
    _isLoadingLatestItems = true;
    _latestItemsError = null;
    notifyListeners();
    try {
      final page = await _latest.getLatest(user: _latestUserId());
      _latestItems = _filterLatestMarked(page.items);
      _latestBefore = page.nextBefore;
      _hasMoreLatestItems = page.items.isNotEmpty && page.nextBefore != null;
    } on LatestMfunsException catch (error) {
      _latestItemsError = error.message;
    } finally {
      _isLoadingLatestItems = false;
      notifyListeners();
    }
  }

  Future<void> loadMoreLatestItems() async {
    if (_isLoadingMoreLatestItems ||
        !_hasMoreLatestItems ||
        _latestBefore == null) {
      return;
    }
    _isLoadingMoreLatestItems = true;
    _latestItemsError = null;
    notifyListeners();
    try {
      final page =
          await _latest.getLatest(before: _latestBefore, user: _latestUserId());
      final ids = _latestItems.map((item) => item.stableId).toSet();
      final additions = _filterLatestMarked(page.items)
          .where((item) => !ids.contains(item.stableId))
          .toList(growable: false);
      _latestItems = [..._latestItems, ...additions];
      _latestBefore = page.nextBefore;
      _hasMoreLatestItems = additions.isNotEmpty && page.nextBefore != null;
    } on LatestMfunsException catch (error) {
      _latestItemsError = error.message;
    } finally {
      _isLoadingMoreLatestItems = false;
      notifyListeners();
    }
  }

  /// 最新页标记使用登录用户 UID；未登录返回空（服务端忽略）。
  String _latestUserId() => _session?.userId?.toString() ?? '';

  /// 不友好标记（必须登录）：服务端按 UID 记录，同一用户只计一次；
  /// 达到 5 人后帖子被服务端屏蔽并从列表移除。
  /// 标记后本地记住资源 id，刷新时过滤，不再重新出现。
  Future<LatestMarkResult> markLatestItem(LatestMfunsItem item) async {
    final userId = _session?.userId;
    if (userId == null) {
      throw const LatestMfunsException('请先登录后再标记');
    }
    final result = await _latest.markItem(
      id: item.id,
      type: item.type,
      user: '$userId',
    );
    _latestMarkedIds.add(item.stableId);
    final marked =
        item.copyWith(markCount: result.markCount, markedByMe: true);
    final updated = <LatestMfunsItem>[];
    for (final existing in _latestItems) {
      if (existing.stableId != item.stableId) {
        updated.add(existing);
      } else if (!result.blocked) {
        updated.add(marked);
      }
    }
    _latestItems = updated;
    notifyListeners();
    return result;
  }

  /// 取消不友好标记（必须登录）；帖子被屏蔽后无法再取消。
  Future<LatestMarkResult> unmarkLatestItem(LatestMfunsItem item) async {
    final userId = _session?.userId;
    if (userId == null) {
      throw const LatestMfunsException('请先登录后再操作');
    }
    final result = await _latest.cancelMark(
      id: item.id,
      type: item.type,
      user: '$userId',
    );
    _latestMarkedIds.remove(item.stableId);
    final unmarked =
        item.copyWith(markCount: result.markCount, markedByMe: false);
    final updated = <LatestMfunsItem>[];
    for (final existing in _latestItems) {
      updated.add(
          existing.stableId == item.stableId ? unmarked : existing);
    }
    _latestItems = updated;
    notifyListeners();
    return result;
  }

  Future<void> _refreshTimeline({required bool following}) async {
    _setTimelineLoading(following: following, loading: true);
    _setTimelineError(following: following, value: null);
    notifyListeners();
    try {
      final result = following
          ? await _home.getFeeds(
              startId: -1,
              following: true,
              userId: _session?.userId,
            )
          : await _home.getTimelineFeeds(page: 1);
      _setTimelineItems(following: following, items: result);
      _setTimelineHasMore(following: following, value: result.isNotEmpty);
      if (!following) _timelinePage = 1;
    } on MfunsApiException catch (error) {
      _setTimelineError(following: following, value: error.message);
    } finally {
      _setTimelineLoading(following: following, loading: false);
      notifyListeners();
    }
  }

  Future<void> _loadMoreTimeline({required bool following}) async {
    final loadingMore =
        following ? _isLoadingMoreFollowingFeeds : _isLoadingMoreFeeds;
    final hasMore = following ? _hasMoreFollowingFeeds : _hasMoreFeeds;
    final items = following ? _followingFeeds : _feeds;
    if (loadingMore || !hasMore || items.isEmpty) return;

    _setTimelineLoadingMore(following: following, loading: true);
    _setTimelineError(following: following, value: null);
    notifyListeners();
    try {
      final result = following
          ? await _home.getFeeds(
              startId: items.last.id,
              following: true,
              userId: _session?.userId,
            )
          : await _home.getTimelineFeeds(page: _timelinePage + 1);
      final existingIds = items.map((item) => item.id).toSet();
      final additions = result
          .where((item) => !existingIds.contains(item.id))
          .toList(growable: false);
      _setTimelineItems(following: following, items: [...items, ...additions]);
      if (!following && result.isNotEmpty) _timelinePage++;
      _setTimelineHasMore(
        following: following,
        value: result.isNotEmpty && additions.isNotEmpty,
      );
    } on MfunsApiException catch (error) {
      _setTimelineError(following: following, value: error.message);
    } finally {
      _setTimelineLoadingMore(following: following, loading: false);
      notifyListeners();
    }
  }

  void _setTimelineItems({
    required bool following,
    required List<TimelineFeed> items,
  }) {
    if (following) {
      _followingFeeds = items;
    } else {
      _feeds = items;
    }
  }

  void _setTimelineError({required bool following, required String? value}) {
    if (following) {
      _followingFeedsError = value;
    } else {
      _feedsError = value;
    }
  }

  void _setTimelineLoading({required bool following, required bool loading}) {
    if (following) {
      _isLoadingFollowingFeeds = loading;
    } else {
      _isLoadingFeeds = loading;
    }
  }

  void _setTimelineLoadingMore({
    required bool following,
    required bool loading,
  }) {
    if (following) {
      _isLoadingMoreFollowingFeeds = loading;
    } else {
      _isLoadingMoreFeeds = loading;
    }
  }

  void _setTimelineHasMore({required bool following, required bool value}) {
    if (following) {
      _hasMoreFollowingFeeds = value;
    } else {
      _hasMoreFeeds = value;
    }
  }

  double? _historyCursor;
  bool _hasMoreHistory = false;
  bool _isLoadingMoreHistory = false;
  List<BackpackItem> _backpack = const [];
  bool _isLoadingBackpack = false;
  String? _backpackError;

  Future<void> loadHistory() async {
    _isLoadingHistory = true;
    _historyError = null;
    notifyListeners();
    try {
      final page = await _home.getHistory();
      _history = page.items;
      _historyCursor = page.nextStartTime;
      _hasMoreHistory = page.items.isNotEmpty && page.nextStartTime != null;
    } on MfunsApiException catch (error) {
      _historyError = error.message;
    } finally {
      _isLoadingHistory = false;
      notifyListeners();
    }
  }

  Future<void> loadMoreHistory() async {
    if (_isLoadingMoreHistory || !_hasMoreHistory || _historyCursor == null) {
      return;
    }
    _isLoadingMoreHistory = true;
    notifyListeners();
    try {
      final page = await _home.getHistory(startTime: _historyCursor);
      final seen = _history.map((item) => item.id).toSet();
      final additions = page.items
          .where((item) => !seen.contains(item.id))
          .toList(growable: false);
      _history = [..._history, ...additions];
      _historyCursor = page.nextStartTime;
      _hasMoreHistory = additions.isNotEmpty && page.nextStartTime != null;
    } on MfunsApiException {
      // 滚动到底可再次触发加载。
    } finally {
      _isLoadingMoreHistory = false;
      notifyListeners();
    }
  }

  /// 我的资产：加载背包道具（需登录），喵币余额随会话刷新。
  Future<void> loadBackpack() async {
    if (_session == null) {
      _backpack = const [];
      _backpackError = '登录后可查看背包道具';
      notifyListeners();
      return;
    }
    _isLoadingBackpack = true;
    _backpackError = null;
    notifyListeners();
    try {
      _backpack = await _home.getUserBackpack();
    } on MfunsApiException catch (error) {
      _backpackError = error.message;
    } finally {
      _isLoadingBackpack = false;
      notifyListeners();
    }
  }

  Future<void> loadFavoriteFolders() async {
    final userId = _session?.userId;
    if (userId == null) {
      _favoritesError = '登录后可查看收藏夹';
      notifyListeners();
      return;
    }
    _isLoadingFavorites = true;
    _favoritesError = null;
    notifyListeners();
    try {
      _favoriteFolders = await _home.getFavoriteFolders(userId);
    } on MfunsApiException catch (error) {
      _favoritesError = error.message;
    } finally {
      _isLoadingFavorites = false;
      notifyListeners();
    }
  }

  Future<void> loadFavoriteItems(int favoriteId, {bool loadMore = false}) async {
    if (loadMore) {
      if (_isLoadingMoreFavorites || !_hasMoreFavoriteItems) return;
      _isLoadingMoreFavorites = true;
      notifyListeners();
      try {
        final page = await _home.getFavoriteItemsPage(
          favoriteId,
          lastId: _favoriteItemsLastId,
        );
        final knownIds = _favoriteItems.map((item) => item.id).toSet();
        final newItems = page.items
            .where((item) => !knownIds.contains(item.id))
            .toList(growable: false);
        if (newItems.isEmpty) {
          // The server repeated content for this cursor: nothing new to add.
          _hasMoreFavoriteItems = false;
          return;
        }
        _favoriteItems = [..._favoriteItems, ...newItems];
        _favoriteItemsLastId = page.nextLastId ?? _favoriteItemsLastId;
        _hasMoreFavoriteItems = page.nextLastId != null;
      } on MfunsApiException catch (error) {
        _favoritesError = error.message;
      } finally {
        _isLoadingMoreFavorites = false;
        notifyListeners();
      }
      return;
    }
    _isLoadingFavorites = true;
    _favoritesError = null;
    _favoriteItemsLastId = 0;
    _hasMoreFavoriteItems = true;
    notifyListeners();
    try {
      final page = await _home.getFavoriteItemsPage(favoriteId);
      _favoriteItems = page.items;
      _favoriteItemsLastId = page.nextLastId ?? 0;
      _hasMoreFavoriteItems = page.nextLastId != null;
    } on MfunsApiException catch (error) {
      _favoritesError = error.message;
    } finally {
      _isLoadingFavorites = false;
      notifyListeners();
    }
  }

  Future<String?> login(String account, String password) async {
    _isLoggingIn = true;
    notifyListeners();
    try {
      _session = await _auth.login(account: account.trim(), password: password);
      await _sessionStore.saveToken(_session!.accessToken);
      await loadFavoriteFolders();
      _startUnreadPolling();
      return null;
    } on MfunsApiException catch (error) {
      return error.message;
    } finally {
      _isLoggingIn = false;
      notifyListeners();
    }
  }

  Future<void> clearLocalSession() async {
    _api.clearAccessToken();
    _session = null;
    _stopUnreadPolling();
    notifyListeners();
    await _sessionStore.clear();
  }

  Future<ContentDetail> contentDetail(ContentPreview preview) =>
      _home.getDetail(preview);

  Future<FeedDetail> feedDetail(int feedId) => _home.getFeedDetail(feedId);

  Future<List<ContentPreview>> relatedContent(ContentPreview preview) =>
      _home.getRelated(preview);

  Future<List<VideoQuality>> videoQualities(int videoId) =>
      _home.getVideoQualities(videoId);

  Future<List<CommunityComment>> comments(int areaId, {int page = 1}) =>
      _home.getComments(areaId, page: page);

  Future<List<CommunityComment>> commentReplies(
    int commentId, {
    int page = 1,
  }) =>
      _home.getCommentReplies(commentId, page: page);

  Future<void> createComment({
    required int areaId,
    required List<CommentSpan> spans,
    List<String> images = const [],
  }) =>
      _home.createComment(areaId: areaId, spans: spans, images: images);

  Future<String> uploadImage(List<int> bytes, String filename) =>
      _home.uploadImage(bytes, filename);

  Future<void> createCommentReply({
    required int commentId,
    required List<CommentSpan> spans,
  }) =>
      _home.createCommentReply(commentId: commentId, spans: spans);

  Future<void> deleteComment(int commentId) => _home.deleteComment(commentId);

  /// 投币（需登录）：type 0=文章、1=视频，成功返回服务端消息。
  Future<String> reward({
    required int resourceId,
    required int resourceType,
    int count = 1,
  }) =>
      _home.reward(
          resourceId: resourceId, resourceType: resourceType, count: count);

  Future<void> setCommentReaction({
    required int commentId,
    required bool like,
  }) =>
      _home.setCommentReaction(commentId: commentId, like: like);

  Future<void> deleteFeed(int feedId) => _home.deleteFeed(feedId);

  Future<List<UserProfile>> followList({
    required int userId,
    required String type,
    int lastId = -1,
  }) =>
      _home.getFollowList(userId: userId, type: type, lastId: lastId);

  /// 搜索用户（@ 提及用）。
  Future<List<UserProfile>> searchUsers(String keyword) =>
      _home.searchUsers(keyword);

  Future<List<DanmakuItem>> danmaku(int videoId, int part) =>
      _home.getDanmaku(videoId, part);

  Future<List<MessageConversation>> messageConversations() =>
      _home.getMessageConversations();

  Future<List<MessageRecord>> messageRecord(int userId) =>
      _home.getMessageRecord(userId);

  Future<void> sendMessage({
    required int toUid,
    required List<CommentSpan> spans,
    List<String> images = const [],
  }) =>
      _home.sendMessage(toUid: toUid, spans: spans, images: images);

  Future<NotifyCounts> notifyCounts() => _home.getNotifyCounts();

  /// 未读总数（私信 + 通知），用于底部导航“消息”小红点。
  int get unreadCount => _unreadCount;

  /// 未读通知数（赞/评论/提及/系统），用于消息中心的“通知”标签红点。
  int get notifyUnread => _notifyUnread;

  /// 未读通知明细（与红点同一数据源，保证同步显示）。
  NotifyCounts get notifyCountsData =>
      _lastNotifyCounts ??
      const NotifyCounts(like: 0, comment: 0, mention: 0, system: 0);

  /// 登录后每 30 秒轮询未读数；新消息/赞/评论/提及/系统通知按类型
  /// 弹前台通知，未读总数与红点同步更新。
  /// 私信与通知未读统一取自 `/v1/notify/count`（含 message 字段），
  /// 与服务端同一数据源，查看相关页面后即视为已读。
  Future<void> refreshUnreadCounts() async {
    if (_session == null) return;
    try {
      final counts = await _home.getNotifyCounts();
      final previous = _lastNotifyCounts;
      if (previous != null) {
        if (counts.message > previous.message) {
          LocalMessageNotifier.instance
              .showDm(counts.message - previous.message);
        }
        if (counts.like > previous.like) {
          LocalMessageNotifier.instance
              .showLikes(counts.like - previous.like);
        }
        if (counts.comment > previous.comment) {
          LocalMessageNotifier.instance
              .showComments(counts.comment - previous.comment);
        }
        if (counts.mention > previous.mention) {
          LocalMessageNotifier.instance
              .showMentions(counts.mention - previous.mention);
        }
        if (counts.system > previous.system) {
          LocalMessageNotifier.instance
              .showSystem(counts.system - previous.system);
        }
      }
      _lastNotifyCounts = counts;
      final notifyTotal = counts.like +
          counts.comment +
          counts.mention +
          counts.system;
      final total = notifyTotal + counts.message;
      if (total != _unreadCount || notifyTotal != _notifyUnread) {
        _unreadCount = total;
        _notifyUnread = notifyTotal;
        notifyListeners();
      }
    } on MfunsApiException {
      // 网络/接口异常时静默，等待下一轮。
    }
  }

  void _startUnreadPolling() {
    _unreadTimer?.cancel();
    _unreadTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      refreshUnreadCounts();
    });
    refreshUnreadCounts();
  }

  void _stopUnreadPolling() {
    _unreadTimer?.cancel();
    _unreadTimer = null;
    _unreadCount = 0;
    _notifyUnread = 0;
    _lastNotifyCounts = null;
  }

  Future<List<NotifyItem>> notifications({required int type, int page = 1}) =>
      _home.getNotifications(type: type, page: page);

  Future<int?> commentAreaId(int commentId) =>
      _home.getCommentAreaId(commentId);

  Future<(int, int)?> commentResource(int commentId) =>
      _home.getCommentResource(commentId);

  Future<List<SubmissionItem>> submissions({
    required int type,
    int page = 1,
    int size = 20,
    int? status,
  }) =>
      _home.getSubmissions(type: type, page: page, size: size, status: status);

  Future<int> submissionCount(int type) => _home.getSubmissionTotal(type);

  /// Article + video submission counts, used by the profile stat card.
  Future<void> loadSubmissionCounts() async {
    try {
      final results = await Future.wait([
        _home.getSubmissionTotal(0),
        _home.getSubmissionTotal(1),
      ]);
      _submissionTotal = results[0] + results[1];
      notifyListeners();
    } on MfunsApiException {
      // 保持上次数值。
    }
  }

  Future<SubmissionDetail> submissionDetail(int contributeId) =>
      _home.getSubmissionDetail(contributeId);

  Future<void> createArticleSubmission({
    required String title,
    required String content,
    required int categoryId,
    List<String> tags = const [],
    int copyright = 2,
    String cover = '',
    bool draft = false,
  }) =>
      _home.createArticleSubmission(
          title: title,
          content: content,
          categoryId: categoryId,
          tags: tags,
          copyright: copyright,
          cover: cover,
          draft: draft);

  Future<void> updateArticleSubmission({
    required int contributeId,
    required String title,
    required String content,
    required int categoryId,
    List<String> tags = const [],
    int copyright = 2,
    String cover = '',
    bool draft = false,
  }) =>
      _home.updateArticleSubmission(
          contributeId: contributeId,
          title: title,
          content: content,
          categoryId: categoryId,
          tags: tags,
          copyright: copyright,
          cover: cover,
          draft: draft);

  Future<void> updateVideoSubmission({
    required int contributeId,
    required String title,
    required String content,
    required int categoryId,
    List<String> tags = const [],
    int copyright = 0,
    String cover = '',
  }) =>
      _home.updateVideoSubmission(
          contributeId: contributeId,
          title: title,
          content: content,
          categoryId: categoryId,
          tags: tags,
          copyright: copyright,
          cover: cover);

  Future<void> deleteSubmission({
    required int type,
    required int contributeId,
  }) =>
      _home.deleteSubmission(type: type, contributeId: contributeId);

  Future<VideoUploadAuth> videoUploadAuth({
    required String fileName,
    required int fileSize,
  }) =>
      _home.getVideoUploadAuth(fileName: fileName, fileSize: fileSize);

  Future<int> completeVideoUpload(String videoId) =>
      _home.completeVideoUpload(videoId);

  Future<void> createVideoSubmission({
    required String title,
    required String content,
    required int categoryId,
    required int videoLibraryId,
    List<String> tags = const [],
    int copyright = 0,
    String cover = '',
  }) =>
      _home.createVideoSubmission(
          title: title,
          content: content,
          categoryId: categoryId,
          videoLibraryId: videoLibraryId,
          tags: tags,
          copyright: copyright,
          cover: cover);

  Future<void> createFeed({
    required String content,
    List<String> images = const [],
    List<String> tags = const [],
  }) =>
      _home.createFeed(content: content, images: images, tags: tags);

  Future<void> updateUserName(String name) => _home.updateUserName(name);

  Future<void> updateUserBio(String bio) => _home.updateUserBio(bio);

  Future<void> updateUserGender(int gender) => _home.updateUserGender(gender);

  Future<void> updateUserAvatar(String path) =>
      _home.updateUserAvatar(path);

  /// Re-fetches the current session so profile edits (name/avatar) show up
  /// everywhere immediately.
  Future<void> refreshSession() async {
    final session = _session;
    if (session == null) return;
    try {
      final restored = await _auth.restore(session.accessToken);
      if (restored != null) {
        _session = restored;
        notifyListeners();
      }
    } on MfunsApiException {
      // 会话失效时保持现状，由其它入口处理。
    }
  }

  Future<(int, int)?> commentAreaInfo(int areaId) =>
      _home.getCommentAreaInfo(areaId);

  Future<UserProfile> userProfile(int userId) => _home.getUserProfile(userId);

  Future<List<TimelineFeed>> userFeeds({
    required int userId,
    int startId = -1,
  }) =>
      _home.getFeeds(startId: startId, following: false, userId: userId);

  Future<List<ContentPreview>> userArticles({
    required int userId,
    int cursor = 0,
  }) =>
      _home.getUserArticles(userId: userId, cursor: cursor);

  Future<List<ContentPreview>> userVideos({
    required int userId,
    int cursor = 0,
  }) =>
      _home.getUserVideos(userId: userId, cursor: cursor);

  Future<ResourceReactionStatus> reactionStatus({
    required int resourceId,
    required int resourceType,
  }) =>
      _home.getReactionStatus(
        resourceId: resourceId,
        resourceType: resourceType,
      );

  Future<void> setReaction({
    required int resourceId,
    required int resourceType,
    required String action,
  }) =>
      _home.setReaction(
        resourceId: resourceId,
        resourceType: resourceType,
        action: action,
      );

  Future<bool> isFavorite({
    required int resourceId,
    required int resourceType,
  }) =>
      _home.isFavorite(
        resourceId: resourceId,
        resourceType: resourceType,
      );

  Future<bool> followStatus(int userId) => _home.followStatus(userId);

  Future<void> setFollow({required int userId, required bool follow}) =>
      _home.setFollow(userId: userId, follow: follow);

  Future<void> addFavorite({
    required int listId,
    required int resourceId,
    required int resourceType,
  }) =>
      _home.addFavorite(
        listId: listId,
        resourceId: resourceId,
        resourceType: resourceType,
      );

  Future<void> removeFavorite({
    required int listId,
    required int resourceId,
    required int resourceType,
  }) =>
      _home.removeFavorite(
        listId: listId,
        resourceId: resourceId,
        resourceType: resourceType,
      );

  Future<void> sendDanmaku({
    required int videoId,
    required int part,
    required double seconds,
    required String content,
    int type = 1,
  }) =>
      _home.sendDanmaku(
        videoId: videoId,
        part: part,
        seconds: seconds,
        content: content,
        type: type,
      );
}
