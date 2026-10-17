import 'package:flutter/material.dart';

import '../models/user.dart';
import '../state/auth_controller.dart';
import '../state/notes_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/note_editor_dialog.dart';
import 'dashboard_view.dart';
import 'notes_view.dart';

/// Authenticated app frame: adaptive sidebar (or drawer), top navigation with
/// search + Add Note, and the routed page content.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.auth, required this.notes});

  final AuthController auth;
  final NotesController notes;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const double _sidebarWidth = 260;
  static const double _wideBreakpoint = 1000;

  String _page = 'dashboard';
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Initial data load; failures are rendered by the individual views.
    widget.notes.refreshAll().catchError((Object _) => null);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openPage(String page) {
    setState(() => _page = page);
    // Closing the mobile drawer when navigating.
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold?.hasDrawer ?? false) {
      Navigator.of(context).maybePop();
    }
  }

  void _onSearchChanged(String value) {
    // Searching from the dashboard jumps to the notes page so results are
    // visible immediately.
    if (_page != 'notes' && value.isNotEmpty) {
      setState(() => _page = 'notes');
    }
    widget.notes.setSearch(value);
  }

  Future<void> _logout() async {
    widget.notes.reset();
    await widget.auth.logout();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Signed out. See you soon!')),
      );
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? Colors.red.shade700 : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= _wideBreakpoint;

    return Scaffold(
      backgroundColor: AppTheme.background,
      drawer: wide
          ? null
          : Drawer(
              width: _sidebarWidth,
              backgroundColor: AppTheme.surface,
              child: _Sidebar(
                page: _page,
                user: widget.auth.user,
                onNavigate: _openPage,
                onLogout: _logout,
              ),
            ),
      body: Row(
        children: [
          if (wide)
            Container(
              width: _sidebarWidth,
              decoration: const BoxDecoration(
                color: AppTheme.surface,
                border: Border(right: BorderSide(color: AppTheme.border)),
              ),
              child: _Sidebar(
                page: _page,
                user: widget.auth.user,
                onNavigate: _openPage,
                onLogout: _logout,
              ),
            ),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  title: _page == 'dashboard' ? 'Dashboard' : 'My Notes',
                  wide: wide,
                  searchController: _search,
                  onMenu: () => Scaffold.of(context).openDrawer(),
                  onSearchChanged: _onSearchChanged,
                  onAddNote: _createNote,
                  user: widget.auth.user,
                  onLogout: _logout,
                ),
                const Divider(),
                Expanded(
                  child: IndexedStack(
                    index: _page == 'dashboard' ? 0 : 1,
                    children: [
                      DashboardView(
                        notes: widget.notes,
                        userName: widget.auth.user?.name ?? '',
                        onAddNote: _createNote,
                        onOpenNotes: () => _openPage('notes'),
                      ),
                      NotesView(
                        notes: widget.notes,
                        onAddNote: _createNote,
                        onNotify: _snack,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createNote() async {
    final saved = await showNoteEditor(context, notes: widget.notes);
    if (saved == true) _snack('Note saved.');
  }
}

/// Left navigation: brand, page links, and the signed-in user footer.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.page,
    required this.user,
    required this.onNavigate,
    required this.onLogout,
  });

  final String page;
  final User? user;
  final ValueChanged<String> onNavigate;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    gradient: AppTheme.brandGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'LockNote',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 28),
            _NavTile(
              icon: Icons.dashboard_rounded,
              label: 'Dashboard',
              selected: page == 'dashboard',
              onTap: () => onNavigate('dashboard'),
            ),
            const SizedBox(height: 6),
            _NavTile(
              icon: Icons.sticky_note_2_rounded,
              label: 'My Notes',
              selected: page == 'notes',
              onTap: () => onNavigate('notes'),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                children: [
                  _Avatar(initials: user?.initials ?? '?', size: 36),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.name ?? 'Signed in',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          user?.email ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Tooltip(
                    message: 'Sign out',
                    child: IconButton(
                      onPressed: onLogout,
                      icon: const Icon(Icons.logout_rounded, size: 19),
                      color: AppTheme.textSecondary,
                      visualDensity: VisualDensity.compact,
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
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppTheme.primary.withValues(alpha: 0.1)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? AppTheme.primary : AppTheme.textSecondary,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppTheme.primary : AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Top navigation: menu/title, live search, Add Note, and user menu.
class _TopBar extends StatefulWidget {
  const _TopBar({
    required this.title,
    required this.wide,
    required this.searchController,
    required this.onMenu,
    required this.onSearchChanged,
    required this.onAddNote,
    required this.user,
    required this.onLogout,
  });

  final String title;
  final bool wide;
  final TextEditingController searchController;
  final VoidCallback onMenu;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onAddNote;
  final User? user;
  final Future<void> Function() onLogout;

  @override
  State<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<_TopBar> {
  @override
  void initState() {
    super.initState();
    // Rebuild when text changes so the clear (x) button appears/disappears.
    widget.searchController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.searchController.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = widget.wide ? 20.0 : 8.0;
    // Width actually available to the bar (viewport minus sidebar and padding).
    final available =
        width -
        (widget.wide ? _HomeShellState._sidebarWidth : 0) -
        horizontalPadding -
        20;
    // When space is tight the search box drops to its own row so the bar can
    // never overflow, no matter how long the titles or translations are.
    final inlineSearch = available >= 860;
    final showShield = available >= 480;
    final showAddLabel = available >= 560;

    final menuButton = IconButton(
      tooltip: 'Open menu',
      onPressed: widget.onMenu,
      icon: const Icon(Icons.menu_rounded),
    );

    final searchField = TextField(
      controller: widget.searchController,
      onChanged: widget.onSearchChanged,
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search notes…',
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: widget.searchController.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  widget.searchController.clear();
                  widget.onSearchChanged('');
                },
              ),
      ),
    );

    final addButton = ElevatedButton.icon(
      onPressed: widget.onAddNote,
      icon: const Icon(Icons.add_rounded, size: 18),
      label: Text(showAddLabel ? 'Add Note' : 'Add'),
    );

    final userMenu = PopupMenuButton<String>(
      tooltip: 'Account menu',
      onSelected: (value) {
        if (value == 'logout') widget.onLogout();
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.user?.name ?? '',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              Text(
                widget.user?.email ?? '',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuItem(value: 'logout', child: Text('Sign out')),
      ],
      child: CircleAvatar(
        radius: 17,
        backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
        child: Text(
          widget.user?.initials ?? '?',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.primary,
          ),
        ),
      ),
    );

    final title = Text(
      widget.title,
      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
    );

    final shield = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Icon(
        Icons.shield_rounded,
        size: 13,
        color: AppTheme.primary,
      ),
    );

    final leading = [
      if (!widget.wide) ...[menuButton, const SizedBox(width: 4)],
    ];

    return Container(
      color: AppTheme.surface,
      padding: EdgeInsets.fromLTRB(horizontalPadding, 14, 20, 14),
      child: inlineSearch
          ? Row(
              children: [
                ...leading,
                title,
                if (showShield) ...[const SizedBox(width: 8), shield],
                const Spacer(),
                SizedBox(width: 300, child: searchField),
                const SizedBox(width: 12),
                addButton,
                const SizedBox(width: 12),
                userMenu,
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    ...leading,
                    title,
                    if (showShield) ...[const SizedBox(width: 8), shield],
                    const Spacer(),
                    userMenu,
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: searchField),
                    const SizedBox(width: 12),
                    addButton,
                  ],
                ),
              ],
            ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initials, required this.size});

  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: AppTheme.primary.withValues(alpha: 0.14),
      child: Text(
        initials,
        style: TextStyle(
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
          color: AppTheme.primary,
        ),
      ),
    );
  }
}
