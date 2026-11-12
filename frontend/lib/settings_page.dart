import 'package:flutter/material.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool notifications = true;
  bool recentArticles = true;
  bool askBeforeTreatment = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              children: [
                _section(
                  'General',
                  [
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.language),
                      title: Text('Language'),
                      subtitle: Text('English / Persian later'),
                      trailing: Icon(Icons.chevron_right),
                    ),
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.palette_outlined),
                      title: Text('Appearance'),
                      subtitle: Text('Light theme'),
                      trailing: Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _section(
                  'Clinical AI preferences',
                  [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: recentArticles,
                      onChanged: (v) => setState(() => recentArticles = v),
                      title: const Text('Include recent literature'),
                      subtitle: const Text(
                        'Retrieve relevant current articles for each analyzed case.',
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: askBeforeTreatment,
                      onChanged: (v) => setState(() => askBeforeTreatment = v),
                      title: const Text('Show treatment warning'),
                      subtitle: const Text(
                        'Keep explicit clinician-review warning before treatment considerations.',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _section(
                  'Account & notifications',
                  [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: notifications,
                      onChanged: (v) => setState(() => notifications = v),
                      title: const Text('Notifications'),
                    ),
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.local_hospital_outlined),
                      title: Text('Clinic information'),
                      trailing: Icon(Icons.chevron_right),
                    ),
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.privacy_tip_outlined),
                      title: Text('Privacy & data'),
                      trailing: Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE4ECEC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}
