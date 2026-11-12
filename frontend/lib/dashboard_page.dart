
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'new_case_wizard.dart';
import 'my_cases_page.dart';
import 'profile_page.dart';
import 'settings_page.dart';
import 'reproduction_hub_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  final _searchController = TextEditingController();

  final List<_AppNotification> _notifications = [
    _AppNotification(
      title: 'Notification center is ready',
      message:
          'Clinical alerts, completed analyses and account notices will appear here.',
      timeLabel: 'System',
      isRead: false,
      icon: Icons.notifications_active_outlined,
    ),
  ];

  @override
  void initState() {
    super.initState();

    _clockTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) {
        if (!mounted) return;
        setState(() {
          _now = DateTime.now();
        });
      },
    );
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  bool get _isNight {
    final hour = _now.hour;
    return hour < 6 || hour >= 18;
  }

  String get _greeting {
    final hour = _now.hour;

    if (hour >= 5 && hour < 12) {
      return 'Good morning';
    }

    if (hour >= 12 && hour < 17) {
      return 'Good afternoon';
    }

    if (hour >= 17 && hour < 21) {
      return 'Good evening';
    }

    return 'Good night';
  }

  String get _registeredName {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      return '';
    }

    final rawName = user.userMetadata?['full_name']?.toString().trim() ?? '';

    if (rawName.isNotEmpty) {
      return rawName;
    }

    final email = user.email?.trim() ?? '';

    if (email.isEmpty) {
      return '';
    }

    return email.split('@').first;
  }

  String get _doctorLabel {
    final name = _registeredName.trim();

    if (name.isEmpty) {
      return '';
    }

    final lower = name.toLowerCase();

    if (lower.startsWith('dr.') ||
        lower.startsWith('dr ') ||
        lower.startsWith('doctor ')) {
      return name;
    }

    return 'Dr. $name';
  }

  int get _unreadNotificationCount {
    return _notifications.where((item) => !item.isRead).length;
  }

  _DashboardPalette get _palette {
    if (_isNight) {
      return const _DashboardPalette(
        background: Color(0xFF081316),
        sidebar: Color(0xFF071E24),
        sidebarAccent: Color(0xFF0B3138),
        card: Color(0xFF102126),
        cardSoft: Color(0xFF152A30),
        input: Color(0xFF13272C),
        border: Color(0xFF264047),
        textPrimary: Color(0xFFF1F7F7),
        textSecondary: Color(0xFF9CB0B6),
        teal: Color(0xFF1FC1B6),
        tealDark: Color(0xFF0FA49A),
        heroStart: Color(0xFF10383F),
        heroEnd: Color(0xFF123036),
        queueBlue: Color(0xFF142D43),
        queueGold: Color(0xFF382E1B),
        queueGreen: Color(0xFF15352D),
        queueCyan: Color(0xFF12363A),
        shadow: Color(0x00000000),
      );
    }

    return const _DashboardPalette(
      background: Color(0xFFF3F7F7),
      sidebar: Color(0xFF0A6574),
      sidebarAccent: Color(0xFF0D7582),
      card: Colors.white,
      cardSoft: Color(0xFFF7FAFA),
      input: Colors.white,
      border: Color(0xFFDDE8E8),
      textPrimary: Color(0xFF102F46),
      textSecondary: Color(0xFF74878F),
      teal: Color(0xFF0AA7A0),
      tealDark: Color(0xFF087B76),
      heroStart: Color(0xFFF8FCFC),
      heroEnd: Color(0xFFEAF6F5),
      queueBlue: Color(0xFFEAF2FF),
      queueGold: Color(0xFFFFF1DD),
      queueGreen: Color(0xFFE5F7EE),
      queueCyan: Color(0xFFE5F6F4),
      shadow: Color(0x12000000),
    );
  }

  void _openPage(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => page,
      ),
    );
  }

  void _startNewCase() {
    _openPage(const NewCaseWizard());
  }

  void _showNotReady(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _palette.tealDark,
        content: Text(
          '$feature will be connected to real case data in the next build step.',
        ),
      ),
    );
  }

  void _handleSearch(String value) {
    final query = value.trim();

    if (query.isEmpty) {
      return;
    }

    _showNotReady('Search for "$query"');
  }

  Future<void> _openNotifications() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: _palette.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(26),
                side: BorderSide(
                  color: _palette.border,
                ),
              ),
              child: SizedBox(
                width: 560,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: _palette.teal.withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.notifications_none_rounded,
                              color: _palette.teal,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Notifications',
                                  style: TextStyle(
                                    color: _palette.textPrimary,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Case, report and account alerts',
                                  style: TextStyle(
                                    color: _palette.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_unreadNotificationCount > 0)
                            TextButton(
                              onPressed: () {
                                for (final item in _notifications) {
                                  item.isRead = true;
                                }

                                setDialogState(() {});
                                setState(() {});
                              },
                              child: const Text('Mark all read'),
                            ),
                          IconButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: Icon(
                              Icons.close,
                              color: _palette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _notifications.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final item = _notifications[index];

                            return InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () {
                                item.isRead = true;
                                setDialogState(() {});
                                setState(() {});
                              },
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: item.isRead
                                      ? _palette.cardSoft
                                      : _palette.teal.withValues(alpha: .10),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: item.isRead
                                        ? _palette.border
                                        : _palette.teal.withValues(alpha: .30),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      item.icon,
                                      color: _palette.teal,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  item.title,
                                                  style: TextStyle(
                                                    color: _palette.textPrimary,
                                                    fontWeight: item.isRead
                                                        ? FontWeight.w600
                                                        : FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                item.timeLabel,
                                                style: TextStyle(
                                                  color:
                                                      _palette.textSecondary,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 5),
                                          Text(
                                            item.message,
                                            style: TextStyle(
                                              color: _palette.textSecondary,
                                              height: 1.45,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showProfileMenu() {
    showMenu<String>(
      context: context,
      position: const RelativeRect.fromLTRB(1000, 76, 30, 0),
      color: _palette.card,
      items: [
        PopupMenuItem(
          value: 'profile',
          child: Row(
            children: [
              Icon(
                Icons.person_outline,
                color: _palette.teal,
              ),
              const SizedBox(width: 10),
              Text(
                'My Profile',
                style: TextStyle(
                  color: _palette.textPrimary,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'settings',
          child: Row(
            children: [
              Icon(
                Icons.settings_outlined,
                color: _palette.teal,
              ),
              const SizedBox(width: 10),
              Text(
                'Settings',
                style: TextStyle(
                  color: _palette.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    ).then(
      (value) {
        if (value == 'profile') {
          _openPage(const ProfilePage());
        }

        if (value == 'settings') {
          _openPage(const SettingsPage());
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palette;

    return Scaffold(
      backgroundColor: palette.background,
      body: Row(
        children: [
          _Sidebar(
            palette: palette,
            onDashboard: () {},
            onNewCase: _startNewCase,
            onMyCases: () => _openPage(
              const MyCasesPage(),
            ),
            onReproduction: () => _openPage(const ReproductionHubPage()),
            onEvidence: () => _openPage(
              _SimpleWorkspacePage(
                title: 'Evidence Library',
                subtitle:
                    'Search guidelines, articles and saved references from one place.',
                icon: Icons.auto_stories_outlined,
                palette: palette,
              ),
            ),
            onKnowledge: () => _openPage(
              _SimpleWorkspacePage(
                title: 'Knowledge Base',
                subtitle:
                    'Your approved veterinary textbooks and clinical references will live here.',
                icon: Icons.menu_book_outlined,
                palette: palette,
              ),
            ),
            onSettings: () => _openPage(const SettingsPage()),
            onProfile: () => _openPage(const ProfilePage()),
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  palette: palette,
                  greeting: _greeting,
                  doctorLabel: _doctorLabel,
                  searchController: _searchController,
                  unreadCount: _unreadNotificationCount,
                  onSearch: _handleSearch,
                  onNotifications: _openNotifications,
                  onProfileTap: _showProfileMenu,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      28,
                      20,
                      28,
                      36,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final stacked = constraints.maxWidth < 1060;

                            if (stacked) {
                              return Column(
                                children: [
                                  _HeroCard(
                                    palette: palette,
                                    doctorLabel: _doctorLabel,
                                    onStartCase: _startNewCase,
                                    onContinueDraft: () =>
                                        _showNotReady('Draft cases'),
                                  ),
                                  const SizedBox(height: 18),
                                  _WorkQueueCard(
                                    palette: palette,
                                    onOpenDrafts: () =>
                                        _showNotReady('Draft cases'),
                                    onViewReports: () =>
                                        _showNotReady('Reports'),
                                  ),
                                ],
                              );
                            }

                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: _HeroCard(
                                    palette: palette,
                                    doctorLabel: _doctorLabel,
                                    onStartCase: _startNewCase,
                                    onContinueDraft: () =>
                                        _showNotReady('Draft cases'),
                                  ),
                                ),
                                const SizedBox(width: 18),
                                Expanded(
                                  flex: 2,
                                  child: _WorkQueueCard(
                                    palette: palette,
                                    onOpenDrafts: () =>
                                        _showNotReady('Draft cases'),
                                    onViewReports: () =>
                                        _showNotReady('Reports'),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 22),
                        _SectionHeader(
                          title: 'Quick Actions',
                          subtitle: 'Start from what you have',
                          palette: palette,
                        ),
                        const SizedBox(height: 12),
                        _QuickActions(
                          palette: palette,
                          onNewCase: _startNewCase,
                          onCbc: _startNewCase,
                          onImaging: _startNewCase,
                          onEvidence: () => _openPage(
                            _SimpleWorkspacePage(
                              title: 'Evidence Library',
                              subtitle:
                                  'Search articles, guidelines and saved references.',
                              icon: Icons.search_rounded,
                              palette: palette,
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final stacked = constraints.maxWidth < 1000;

                            if (stacked) {
                              return Column(
                                children: [
                                  _RecentCasesCard(
                                    palette: palette,
                                    onStartCase: _startNewCase,
                                    onViewAll: () => _openPage(const MyCasesPage()),
                                  ),
                                  const SizedBox(height: 18),
                                  _EvidenceHubCard(
                                    palette: palette,
                                    onOpenLibrary: () => _openPage(
                                      _SimpleWorkspacePage(
                                        title: 'Evidence Library',
                                        subtitle:
                                            'Your evidence workspace is ready for source integration.',
                                        icon: Icons.auto_stories_outlined,
                                        palette: palette,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }

                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: _RecentCasesCard(
                                    palette: palette,
                                    onStartCase: _startNewCase,
                                    onViewAll: () => _openPage(const MyCasesPage()),
                                  ),
                                ),
                                const SizedBox(width: 18),
                                Expanded(
                                  flex: 2,
                                  child: _EvidenceHubCard(
                                    palette: palette,
                                    onOpenLibrary: () => _openPage(
                                      _SimpleWorkspacePage(
                                        title: 'Evidence Library',
                                        subtitle:
                                            'Your evidence workspace is ready for source integration.',
                                        icon: Icons.auto_stories_outlined,
                                        palette: palette,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final _DashboardPalette palette;
  final String greeting;
  final String doctorLabel;
  final TextEditingController searchController;
  final int unreadCount;
  final ValueChanged<String> onSearch;
  final VoidCallback onNotifications;
  final VoidCallback onProfileTap;

  const _TopBar({
    required this.palette,
    required this.greeting,
    required this.doctorLabel,
    required this.searchController,
    required this.unreadCount,
    required this.onSearch,
    required this.onNotifications,
    required this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 82,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: BoxDecoration(
        color: palette.background,
        border: Border(
          bottom: BorderSide(
            color: palette.border.withValues(alpha: .55),
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            greeting,
            style: TextStyle(
              color: palette.tealDark,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 360,
            child: TextField(
              controller: searchController,
              onSubmitted: onSearch,
              style: TextStyle(
                color: palette.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Search cases, patients, evidence...',
                hintStyle: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 13,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: palette.textSecondary,
                ),
                filled: true,
                fillColor: palette.input,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: palette.border,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: palette.border,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: palette.teal,
                    width: 1.4,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                tooltip: 'Notifications',
                onPressed: onNotifications,
                icon: Icon(
                  Icons.notifications_none_rounded,
                  color: palette.textPrimary,
                  size: 26,
                ),
              ),
              if (unreadCount > 0)
                Positioned(
                  right: 5,
                  top: 5,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 17,
                      minHeight: 17,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE64B4B),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: palette.background,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: onProfileTap,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 9,
              ),
              decoration: BoxDecoration(
                color: palette.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: palette.border,
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: palette.teal.withValues(alpha: .12),
                    child: Icon(
                      Icons.person_rounded,
                      color: palette.tealDark,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 9),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 150,
                    ),
                    child: Text(
                      doctorLabel.isEmpty ? 'Account' : doctorLabel,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: palette.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final _DashboardPalette palette;
  final VoidCallback onDashboard;
  final VoidCallback onNewCase;
  final VoidCallback onMyCases;
  final VoidCallback onReproduction;
  final VoidCallback onEvidence;
  final VoidCallback onKnowledge;
  final VoidCallback onSettings;
  final VoidCallback onProfile;

  const _Sidebar({
    required this.palette,
    required this.onDashboard,
    required this.onNewCase,
    required this.onMyCases,
    required this.onReproduction,
    required this.onEvidence,
    required this.onKnowledge,
    required this.onSettings,
    required this.onProfile,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      color: palette.sidebar,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: palette.sidebarAccent,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .14),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Image.asset(
                        'assets/logo.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(width: 11),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Assistant Vet',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Clinical workspace',
                            style: TextStyle(
                              color: Color(0xFFCDE6E8),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _SidebarItem(
                    icon: Icons.space_dashboard_outlined,
                    label: 'Dashboard',
                    active: true,
                    onTap: onDashboard,
                  ),
                  _SidebarItem(
                    icon: Icons.add_circle_outline_rounded,
                    label: 'New Case',
                    onTap: onNewCase,
                  ),
                  _SidebarItem(
                    icon: Icons.folder_copy_outlined,
                    label: 'My Cases',
                    onTap: onMyCases,
                  ),
                  _SidebarItem(
                    icon: Icons.pregnant_woman_outlined,
                    label: 'Obstetrics',
                    onTap: onReproduction,
                  ),
                  const _SidebarDivider(),
                  _SidebarItem(
                    icon: Icons.auto_stories_outlined,
                    label: 'Evidence Library',
                    onTap: onEvidence,
                  ),
                  _SidebarItem(
                    icon: Icons.menu_book_outlined,
                    label: 'Knowledge Base',
                    onTap: onKnowledge,
                  ),
                  _SidebarItem(
                    icon: Icons.settings_outlined,
                    label: 'Settings',
                    onTap: onSettings,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: InkWell(
                onTap: onProfile,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .34),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.person_outline,
                        color: Colors.white,
                        size: 19,
                      ),
                      SizedBox(width: 9),
                      Text(
                        'My Profile',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: active
                ? Colors.white.withValues(alpha: .13)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: Colors.white,
                size: 21,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                  fontSize: 14,
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarDivider extends StatelessWidget {
  const _SidebarDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Divider(
        color: Colors.white.withValues(alpha: .18),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final _DashboardPalette palette;
  final String doctorLabel;
  final VoidCallback onStartCase;
  final VoidCallback onContinueDraft;

  const _HeroCard({
    required this.palette,
    required this.doctorLabel,
    required this.onStartCase,
    required this.onContinueDraft,
  });

  @override
  Widget build(BuildContext context) {
    final welcomeText = doctorLabel.isEmpty
        ? 'Welcome'
        : 'Welcome, $doctorLabel';

    return Container(
      constraints: const BoxConstraints(
        minHeight: 260,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            palette.heroStart,
            palette.heroEnd,
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: palette.border,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 340,
              child: ShaderMask(
                shaderCallback: (bounds) {
                  return LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.transparent,
                      Colors.white.withValues(alpha: .65),
                      Colors.white,
                    ],
                    stops: const [
                      0,
                      .34,
                      1,
                    ],
                  ).createShader(bounds);
                },
                blendMode: BlendMode.dstIn,
                child: Image.asset(
                  'assets/dog_cat.png',
                  fit: BoxFit.cover,
                  alignment: Alignment.centerRight,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(30),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 560,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      welcomeText,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 31,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Start with what you have. Skip what you do not have. Assistant Vet will organize the case before analysis.',
                      style: TextStyle(
                        color: palette.textSecondary,
                        height: 1.55,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 26),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: palette.teal,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: onStartCase,
                          icon: const Icon(
                            Icons.add_circle_outline_rounded,
                          ),
                          label: const Text(
                            'Start New Case',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: palette.tealDark,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 16,
                            ),
                            side: BorderSide(
                              color: palette.tealDark.withValues(alpha: .55),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: onContinueDraft,
                          icon: const Icon(
                            Icons.history_rounded,
                          ),
                          label: const Text(
                            'Continue Draft',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkQueueCard extends StatelessWidget {
  final _DashboardPalette palette;
  final VoidCallback onOpenDrafts;
  final VoidCallback onViewReports;

  const _WorkQueueCard({
    required this.palette,
    required this.onOpenDrafts,
    required this.onViewReports,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        minHeight: 260,
      ),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: palette.border,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.view_quilt_outlined,
                color: palette.teal,
                size: 23,
              ),
              const SizedBox(width: 9),
              Text(
                "Today's Workspace",
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            'Your current clinical workload',
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          _QueueItem(
            palette: palette,
            background: palette.queueBlue,
            icon: Icons.edit_note_rounded,
            value: '0',
            label: 'Draft Cases',
          ),
          const SizedBox(height: 9),
          _QueueItem(
            palette: palette,
            background: palette.queueGold,
            icon: Icons.hourglass_bottom_rounded,
            value: '0',
            label: 'Needs Review',
          ),
          const SizedBox(height: 9),
          _QueueItem(
            palette: palette,
            background: palette.queueGreen,
            icon: Icons.task_alt_rounded,
            value: '0',
            label: 'Reports Ready',
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onOpenDrafts,
                  child: const Text('Open Drafts'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.teal,
                  ),
                  onPressed: onViewReports,
                  child: const Text('View Reports'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QueueItem extends StatelessWidget {
  final _DashboardPalette palette;
  final Color background;
  final IconData icon;
  final String value;
  final String label;

  const _QueueItem({
    required this.palette,
    required this.background,
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        minHeight: 52,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: palette.tealDark,
            size: 21,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final _DashboardPalette palette;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 21,
            fontWeight: FontWeight.w800,
          ),
        ),
        const Spacer(),
        Text(
          subtitle,
          style: TextStyle(
            color: palette.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _QuickActions extends StatelessWidget {
  final _DashboardPalette palette;
  final VoidCallback onNewCase;
  final VoidCallback onCbc;
  final VoidCallback onImaging;
  final VoidCallback onEvidence;

  const _QuickActions({
    required this.palette,
    required this.onNewCase,
    required this.onCbc,
    required this.onImaging,
    required this.onEvidence,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1100
            ? 4
            : width >= 720
                ? 2
                : 1;

        final spacing = 12.0;
        final cardWidth =
            (width - (spacing * (columns - 1))) / columns;

        final actions = [
          (
            Icons.add_circle_outline_rounded,
            'New Case',
            'Guided case workflow',
            onNewCase,
          ),
          (
            Icons.biotech_outlined,
            'Upload CBC',
            'Start from laboratory data',
            onCbc,
          ),
          (
            Icons.image_search_outlined,
            'Imaging',
            'Radiograph or ultrasound',
            onImaging,
          ),
          (
            Icons.auto_stories_outlined,
            'Search Evidence',
            'Articles, guidelines & books',
            onEvidence,
          ),
        ];

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: actions.map(
            (action) {
              return SizedBox(
                width: cardWidth,
                child: _QuickActionCard(
                  palette: palette,
                  icon: action.$1,
                  title: action.$2,
                  subtitle: action.$3,
                  onTap: action.$4,
                ),
              );
            },
          ).toList(),
        );
      },
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final _DashboardPalette palette;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.palette,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        constraints: const BoxConstraints(
          minHeight: 104,
        ),
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: palette.border,
          ),
          boxShadow: [
            BoxShadow(
              color: palette.shadow,
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: palette.teal.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(
                icon,
                color: palette.tealDark,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: palette.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentCasesCard extends StatelessWidget {
  final _DashboardPalette palette;
  final VoidCallback onStartCase;
  final VoidCallback onViewAll;

  const _RecentCasesCard({
    required this.palette,
    required this.onStartCase,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        minHeight: 300,
      ),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: palette.border,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.history_rounded,
                color: palette.teal,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Recent Cases',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: onViewAll,
                child: const Text('View all'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: palette.cardSoft,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: palette.border,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.folder_open_outlined,
                  size: 40,
                  color: palette.textSecondary,
                ),
                const SizedBox(height: 12),
                Text(
                  'No cases yet',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Your real patient cases will appear here after you create the first case.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.teal,
                  ),
                  onPressed: onStartCase,
                  icon: const Icon(
                    Icons.add_circle_outline_rounded,
                  ),
                  label: const Text('Create first case'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceHubCard extends StatelessWidget {
  final _DashboardPalette palette;
  final VoidCallback onOpenLibrary;

  const _EvidenceHubCard({
    required this.palette,
    required this.onOpenLibrary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        minHeight: 300,
      ),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: palette.border,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_stories_outlined,
                color: palette.teal,
              ),
              const SizedBox(width: 9),
              Text(
                'Evidence Hub',
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Your clinical reading workspace',
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 18),
          _EvidenceShortcut(
            palette: palette,
            icon: Icons.article_outlined,
            title: 'Recent literature',
            subtitle: 'Case-relevant articles will appear here',
          ),
          const SizedBox(height: 10),
          _EvidenceShortcut(
            palette: palette,
            icon: Icons.bookmark_outline,
            title: 'Saved references',
            subtitle: 'Keep papers and guidelines for later',
          ),
          const SizedBox(height: 10),
          _EvidenceShortcut(
            palette: palette,
            icon: Icons.menu_book_outlined,
            title: 'Textbook guidance',
            subtitle: 'Book chapters will be linked to case results',
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onOpenLibrary,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Open Evidence Library'),
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceShortcut extends StatelessWidget {
  final _DashboardPalette palette;
  final IconData icon;
  final String title;
  final String subtitle;

  const _EvidenceShortcut({
    required this.palette,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: palette.cardSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: palette.border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: palette.tealDark,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SimpleWorkspacePage extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final _DashboardPalette palette;

  const _SimpleWorkspacePage({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.card,
        foregroundColor: palette.textPrimary,
        surfaceTintColor: palette.card,
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: 620,
          ),
          margin: const EdgeInsets.all(28),
          padding: const EdgeInsets.all(36),
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: palette.border,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: palette.teal,
                size: 52,
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textSecondary,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppNotification {
  final String title;
  final String message;
  final String timeLabel;
  final IconData icon;
  bool isRead;

  _AppNotification({
    required this.title,
    required this.message,
    required this.timeLabel,
    required this.icon,
    required this.isRead,
  });
}

class _DashboardPalette {
  final Color background;
  final Color sidebar;
  final Color sidebarAccent;
  final Color card;
  final Color cardSoft;
  final Color input;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color teal;
  final Color tealDark;
  final Color heroStart;
  final Color heroEnd;
  final Color queueBlue;
  final Color queueGold;
  final Color queueGreen;
  final Color queueCyan;
  final Color shadow;

  const _DashboardPalette({
    required this.background,
    required this.sidebar,
    required this.sidebarAccent,
    required this.card,
    required this.cardSoft,
    required this.input,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.teal,
    required this.tealDark,
    required this.heroStart,
    required this.heroEnd,
    required this.queueBlue,
    required this.queueGold,
    required this.queueGreen,
    required this.queueCyan,
    required this.shadow,
  });
}
