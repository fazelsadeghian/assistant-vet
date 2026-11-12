import 'package:flutter/material.dart';
import 'prostate_size_page.dart';
import 'equine_reproduction_page.dart';

class ReproductionHubPage extends StatelessWidget {
  const ReproductionHubPage({super.key});

  static const ink = Color(0xFF12364C);
  static const teal = Color(0xFF008D86);

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF2F7F8),
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: ink,
          scrolledUnderElevation: 0,
          title: const Text('Obstetrics & Reproduction',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1250),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF083E51), Color(0xFF087F81)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 20,
                      runSpacing: 16,
                      children: [
                        const Icon(Icons.monitor_heart_outlined,
                            color: Colors.white, size: 54),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('REPRODUCTION CENTER',
                                style: TextStyle(
                                    color: Color(0xFF9BEEDE),
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 2)),
                            SizedBox(height: 8),
                            Text('Obstetrics · تولیدمثل و مامایی',
                                style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white)),
                            SizedBox(height: 8),
                            Text('Patient measurements  •  Breeding cycle records  •  Clinical planning',
                                style: TextStyle(color: Color(0xFFD5EFF0))),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text('Clinical workspaces',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900, color: ink)),
                  const SizedBox(height: 6),
                  const Text('Select a tool. Records are saved locally on this Windows computer.',
                      style: TextStyle(color: Color(0xFF67808B))),
                  const SizedBox(height: 22),
                  LayoutBuilder(builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 820;
                    final cards = [
                      _HubCard(
                        imageAsset: 'assets/canine_prostate_ultrasound_illustration_v33.jpg',
                        title: 'Prostate Size',
                        subtitle: 'Canine prostate · سونوگرافی و مقایسهٔ حجم',
                        description: 'محاسبه و ثبت حجم، مقایسه با برآوردهای موجود، تصاویر و روند مراجعات',
                        icon: Icons.monitor_heart_outlined,
                        colors: const [Color(0xFFDEF5EF), Color(0xFFEAFBFA)],
                        onOpen: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ProstateSizePage()),
                        ),
                      ),
                      _HubCard(
                        imageAsset: 'assets/mare_cover_illustration_v33.jpg',
                        title: 'Equine Reproduction',
                        subtitle: 'Mare breeding manager · مدیریت تولیدمثل مادیان',
                        description: 'پرونده و تصویر اسب، فولیکول، گناد، تلقیح تازه/سرد/فریز، خط زمانی و پیشنهادهای علمی',
                        icon: Icons.timeline_outlined,
                        colors: const [Color(0xFFE1EDFF), Color(0xFFF0F6FF)],
                        onOpen: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const EquineReproductionPage()),
                        ),
                      ),
                    ];
                    if (narrow) {
                      return Column(children: [
                        for (final card in cards) ...[card, const SizedBox(height: 16)]
                      ]);
                    }
                    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: 20),
                      Expanded(child: cards[1]),
                    ]);
                  }),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE0EBEC)),
                    ),
                    child: const Row(children: [
                      Icon(Icons.verified_user_outlined, color: teal),
                      SizedBox(width: 12),
                      Expanded(child: Text(
                        'Clinical suggestions are advisory only. Suggested events never appear in the actual timeline until a veterinarian separately records them. Calculations do not establish diagnosis.',
                        style: TextStyle(color: ink, height: 1.45),
                      )),
                    ]),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _HubCard extends StatelessWidget {
  final String title, subtitle, description;
  final String imageAsset;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onOpen;
  const _HubCard({required this.imageAsset, required this.title, required this.subtitle,
    required this.description, required this.icon, required this.colors,
    required this.onOpen});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: onOpen,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0xFFDDE9EA)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: double.infinity,
                height: 168,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    colors: colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(fit: StackFit.expand, children: [
                    Image.asset(imageAsset, fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) =>
                          Center(child: Icon(icon, size: 80,
                            color: const Color(0xFF087E83)))),
                    Positioned(left: 10, bottom: 9,
                      child: Container(padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xDD102E3D),
                          borderRadius: BorderRadius.circular(7)),
                        child: const Text('Educational illustration',
                          style: TextStyle(color: Colors.white, fontSize: 10)))),
                  ]),
                ),
              ),
              const SizedBox(height: 20),
              Text(title, style: const TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 23,
                  color: ReproductionHubPage.ink)),
              const SizedBox(height: 5),
              Text(subtitle, style: const TextStyle(
                  color: ReproductionHubPage.teal, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Text(description, style: const TextStyle(
                  height: 1.5, color: Color(0xFF607986))),
              const SizedBox(height: 22),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                const Text('Open workspace', style: TextStyle(
                    color: ReproductionHubPage.teal, fontWeight: FontWeight.w800)),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_forward_rounded,
                    color: ReproductionHubPage.teal),
              ]),
            ]),
          ),
        ),
      );
}
