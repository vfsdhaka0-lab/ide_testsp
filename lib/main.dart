import 'package:flutter/material.dart';
import 'package:code_text_field/code_text_field.dart';
import 'package:highlight/languages/dart.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart'; 
import '../core/github_service.dart';
import '../models/github_item.dart';
import 'preview_screen.dart';

class EditorScreen extends StatefulWidget {
  final String owner, repo;
  const EditorScreen({super.key, required this.owner, required this.repo});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final GitHubService _service = GitHubService();
  
  // Controller for 1.1.0
  late CodeController _codeController;
  
  GitHubItem? _activeFile;
  String _currentPath = ""; 
  String _buildStatus = 'idle';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // FIX: Removed 'theme' from here to stop the build error
    _codeController = CodeController(
      text: "// Select a file from the drawer",
      language: dart,
    );
    _checkStatus();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _checkStatus() async {
    final status = await _service.getBuildStatus(widget.owner, widget.repo);
    if (mounted) setState(() => _buildStatus = status);
  }

  void _save() async {
    if (_activeFile == null) return;
    setState(() => _isSaving = true);
    final success = await _service.commitFile(
      widget.owner, 
      widget.repo, 
      _activeFile!.path, 
      _codeController.text, 
      _activeFile!.sha
    );
    setState(() => _isSaving = false);
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Changes Saved!"), backgroundColor: Colors.green)
      );
      _checkStatus();
    }
  }

  void _showConsole() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(15))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        height: 350,
        child: Column(
          children: [
            const Text("GIT CONSOLE", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
            const Divider(color: Colors.white12),
            Expanded(
              child: FutureBuilder<List<dynamic>>(
                future: _service.getCommitHistory(widget.owner, widget.repo),
                builder: (ctx, snap) {
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  return ListView.builder(
                    itemCount: snap.data!.length,
                    itemBuilder: (ctx, i) => ListTile(
                      title: Text("> ${snap.data![i]['commit']['message']}", 
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.greenAccent)),
                      subtitle: Text("SHA: ${snap.data![i]['sha'].substring(0,7)}", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _createItem(bool isFolder) {
    TextEditingController _ctrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text("New ${isFolder ? 'Folder' : 'File'}"),
      content: TextField(controller: _ctrl, decoration: InputDecoration(hintText: isFolder ? "folder_name" : "file.dart")),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
        ElevatedButton(onPressed: () async {
          final name = _ctrl.text.trim();
          if (name.isEmpty) return;
          Navigator.pop(ctx);
          String fullPath = "$_currentPath$name${isFolder ? '/.keep' : ''}";
          await _service.commitFile(widget.owner, widget.repo, fullPath, isFolder ? "dir" : "// Created", null);
          setState(() {});
        }, child: const Text("Create"))
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_activeFile?.name ?? "Aman IDE"),
        actions: [
          IconButton(icon: const Icon(Icons.terminal), onPressed: _showConsole),
          IconButton(
            icon: Icon(Icons.play_circle, color: _buildStatus == 'success' ? Colors.green : Colors.orange), 
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (c) => PreviewScreen(url: "https://${widget.owner}.github.io/${widget.repo}/")
            )),
          ),
          _isSaving 
            ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))) 
            : IconButton(icon: const Icon(Icons.save), onPressed: _save),
        ],
      ),
      drawer: Drawer(
        child: Column(children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF1F1F1F)),
            accountName: Text(widget.repo), 
            accountEmail: Text("Path: /$_currentPath")
          ),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            IconButton(icon: const Icon(Icons.note_add), onPressed: () => _createItem(false)),
            IconButton(icon: const Icon(Icons.create_new_folder), onPressed: () => _createItem(true)),
            if (_currentPath.isNotEmpty) IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() {
              var s = _currentPath.split('/')..removeWhere((x) => x.isEmpty);
              if (s.isNotEmpty) s.removeLast();
              _currentPath = s.isEmpty ? "" : "${s.join('/')}/";
            })),
          ]),
          const Divider(),
          Expanded(child: _FileTree(
            owner: widget.owner, 
            repo: widget.repo, 
            path: _currentPath, 
            onSelect: (item) async {
              if (item.isDirectory) { 
                setState(() => _currentPath = "${item.path}/"); 
              } else {
                final raw = await _service.getFileRaw(widget.owner, widget.repo, item.path);
                setState(() { 
                  _activeFile = item; 
                  _codeController.text = raw; 
                });
                Navigator.pop(context);
              }
            }, 
            onRefresh: () => setState(() {}))
          ),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: Container(
            color: const Color(0xFF272822), 
            padding: const EdgeInsets.symmetric(horizontal: 4),
            // THEME FIX for 1.1.0: Using the CodeTheme wrapper to apply colors
            child: CodeTheme(
              data: const CodeThemeData(styles: monokaiSublimeTheme),
              child: CodeField(
                controller: _codeController,
                textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                lineNumberStyle: const LineNumberStyle(
                  width: 45,
                  margin: 10,
                  textStyle: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            ),
          ),
        ),
        GestureDetector(
          onTap: _showConsole, 
          child: Container(
            height: 30, 
            color: Colors.black26, 
            child: Center(child: Text("Status: $_buildStatus", style: const TextStyle(fontSize: 10, color: Colors.grey)))
          )
        ),
      ]),
    );
  }
}

class _FileTree extends StatelessWidget {
  final String owner, repo, path;
  final Function(GitHubItem) onSelect;
  final VoidCallback onRefresh;
  final GitHubService _service = GitHubService();
  
  _FileTree({required this.owner, required this.repo, required this.path, required this.onSelect, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<GitHubItem>>(
      future: _service.getContents(owner, repo, path),
      builder: (ctx, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        return ListView.builder(
          itemCount: snap.data!.length,
          itemBuilder: (ctx, i) {
            final item = snap.data![i];
            return ListTile(
              leading: Icon(item.isDirectory ? Icons.folder : Icons.insert_drive_file, 
                color: item.isDirectory ? Colors.amber : Colors.blueGrey),
              title: Text(item.name, style: const TextStyle(fontSize: 13)),
              onTap: () => onSelect(item),
              onLongPress: () => showDialog(
                context: ctx,
                builder: (d) => AlertDialog(
                  title: const Text("Delete Warning"),
                  content: Text("Are you sure you want to delete '${item.name}'?"),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(d), child: const Text("Keep it")),
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(d);
                        await _service.deleteFile(owner, repo, item.path, item.sha);
                        onRefresh();
                      }, 
                      child: const Text("Delete", style: TextStyle(color: Colors.red))
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
