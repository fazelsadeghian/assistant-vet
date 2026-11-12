import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'verify_email_page.dart';

const Map<String, List<String>> iranLocations = {
  'East Azerbaijan': [
    'Tabriz',
    'Maragheh',
    'Marand',
    'Ahar',
    'Mianeh',
    'Bonab',
    'Sarab',
    'Shabestar',
  ],
  'West Azerbaijan': [
    'Urmia',
    'Khoy',
    'Mahabad',
    'Bukan',
    'Miandoab',
    'Salmas',
    'Naqadeh',
    'Piranshahr',
  ],
  'Ardabil': [
    'Ardabil',
    'Parsabad',
    'Meshgin Shahr',
    'Khalkhal',
    'Germi',
  ],
  'Isfahan': [
    'Isfahan',
    'Kashan',
    'Najafabad',
    'Khomeyni Shahr',
    'Shahin Shahr',
    'Shahreza',
    'Fooladshahr',
  ],
  'Alborz': [
    'Karaj',
    'Fardis',
    'Hashtgerd',
    'Nazarabad',
    'Mohammadshahr',
  ],
  'Ilam': [
    'Ilam',
    'Dehloran',
    'Abdanan',
    'Mehran',
    'Eyvan',
  ],
  'Bushehr': [
    'Bushehr',
    'Borazjan',
    'Genaveh',
    'Kangan',
    'Deyr',
    'Jam',
  ],
  'Tehran': [
    'Tehran',
    'Rey',
    'Shahriar',
    'Eslamshahr',
    'Robat Karim',
    'Varamin',
    'Pakdasht',
    'Damavand',
    'Pardis',
    'Qarchak',
  ],
  'Chaharmahal and Bakhtiari': [
    'Shahrekord',
    'Borujen',
    'Lordegan',
    'Farsan',
  ],
  'South Khorasan': [
    'Birjand',
    'Qaen',
    'Tabas',
    'Ferdows',
    'Nehbandan',
  ],
  'Razavi Khorasan': [
    'Mashhad',
    'Neyshabur',
    'Sabzevar',
    'Torbat Heydarieh',
    'Kashmar',
    'Quchan',
    'Torbat-e Jam',
    'Gonabad',
  ],
  'North Khorasan': [
    'Bojnord',
    'Shirvan',
    'Esfarayen',
    'Jajarm',
  ],
  'Khuzestan': [
    'Ahvaz',
    'Abadan',
    'Khorramshahr',
    'Dezful',
    'Andimeshk',
    'Shushtar',
    'Mahshahr',
    'Behbahan',
    'Masjed Soleyman',
  ],
  'Zanjan': [
    'Zanjan',
    'Abhar',
    'Khorramdarreh',
    'Qeydar',
  ],
  'Semnan': [
    'Semnan',
    'Shahroud',
    'Damghan',
    'Garmsar',
  ],
  'Sistan and Baluchestan': [
    'Zahedan',
    'Zabol',
    'Chabahar',
    'Iranshahr',
    'Saravan',
    'Khash',
  ],
  'Fars': [
    'Shiraz',
    'Marvdasht',
    'Jahrom',
    'Fasa',
    'Kazerun',
    'Lar',
    'Darab',
    'Abadeh',
    'Firuzabad',
  ],
  'Qazvin': [
    'Qazvin',
    'Takestan',
    'Abyek',
    'Alvand',
    'Buin Zahra',
  ],
  'Qom': [
    'Qom',
  ],
  'Kurdistan': [
    'Sanandaj',
    'Saqqez',
    'Baneh',
    'Marivan',
    'Qorveh',
    'Bijar',
  ],
  'Kerman': [
    'Kerman',
    'Sirjan',
    'Rafsanjan',
    'Jiroft',
    'Bam',
    'Zarand',
    'Shahrbabak',
  ],
  'Kermanshah': [
    'Kermanshah',
    'Eslamabad-e Gharb',
    'Javanrud',
    'Paveh',
    'Kangavar',
    'Sarpol-e Zahab',
  ],
  'Kohgiluyeh and Boyer-Ahmad': [
    'Yasuj',
    'Dehdasht',
    'Gachsaran',
  ],
  'Golestan': [
    'Gorgan',
    'Gonbad-e Kavus',
    'Aliabad-e Katul',
    'Bandar Torkaman',
    'Aqqala',
    'Minudasht',
  ],
  'Gilan': [
    'Rasht',
    'Bandar Anzali',
    'Lahijan',
    'Langarud',
    'Rudsar',
    'Astara',
    'Fuman',
    'Sowmeeh Sara',
  ],
  'Lorestan': [
    'Khorramabad',
    'Borujerd',
    'Dorud',
    'Kuhdasht',
    'Aligudarz',
  ],
  'Mazandaran': [
    'Sari',
    'Babol',
    'Amol',
    'Qaem Shahr',
    'Behshahr',
    'Nowshahr',
    'Chalus',
    'Tonekabon',
    'Babolsar',
  ],
  'Markazi': [
    'Arak',
    'Saveh',
    'Khomein',
    'Mahallat',
    'Delijan',
    'Shazand',
  ],
  'Hormozgan': [
    'Bandar Abbas',
    'Qeshm',
    'Kish',
    'Minab',
    'Bandar Lengeh',
    'Rudan',
  ],
  'Hamadan': [
    'Hamadan',
    'Malayer',
    'Nahavand',
    'Tuyserkan',
    'Kabudarahang',
  ],
  'Yazd': [
    'Yazd',
    'Meybod',
    'Ardakan',
    'Bafq',
    'Mehriz',
  ],
};

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _formKey = GlobalKey<FormState>();

  final _fullNameController = TextEditingController();
  final _councilCodeController = TextEditingController();
  final _emailController = TextEditingController();
  final _mobileController = TextEditingController();
  final _provinceController = TextEditingController();
  final _cityController = TextEditingController();
  final _clinicController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String? _selectedProvince;

  bool _hidePassword = true;
  bool _hideConfirmPassword = true;
  bool _acceptedTerms = false;
  bool _loading = false;

  List<String> get _provinces => iranLocations.keys.toList()..sort();

  List<String> get _cities {
    final province = _selectedProvince;
    if (province == null) return const [];
    return List<String>.from(iranLocations[province] ?? const [])..sort();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _councilCodeController.dispose();
    _emailController.dispose();
    _mobileController.dispose();
    _provinceController.dispose();
    _cityController.dispose();
    _clinicController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String _normalizeDigits(String value) {
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const english = '0123456789';

    var result = value.trim();

    for (var i = 0; i < 10; i++) {
      result = result
          .replaceAll(persian[i], english[i])
          .replaceAll(arabic[i], english[i]);
    }

    return result;
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }

    final email = value.trim();

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email address';
    }

    return null;
  }

  String? _validateMobile(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Mobile number is required';
    }

    final mobile = _normalizeDigits(value);

    if (!RegExp(r'^09\d{9}$').hasMatch(mobile)) {
      return 'Enter an 11-digit Iranian mobile number starting with 09';
    }

    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }

    if (value.length < 8) {
      return 'Use at least 8 characters';
    }

    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Add at least one uppercase letter';
    }

    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'Add at least one lowercase letter';
    }

    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'Add at least one number';
    }

    return null;
  }

  void _showMessage(String message, {required bool error}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor:
            error ? const Color(0xFFB43C3C) : const Color(0xFF087B76),
        content: Text(message),
      ),
    );
  }

  Future<String?> _pickFromList({
    required String title,
    required List<String> values,
    required String searchHint,
  }) async {
    final searchController = TextEditingController();
    var filtered = List<String>.from(values);

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void filter(String query) {
              final text = query.trim().toLowerCase();

              setDialogState(() {
                if (text.isEmpty) {
                  filtered = List<String>.from(values);
                } else {
                  filtered = values
                      .where(
                        (item) => item.toLowerCase().contains(text),
                      )
                      .toList();
                }

                filtered.sort((a, b) {
                  final aStarts = a.toLowerCase().startsWith(text);
                  final bStarts = b.toLowerCase().startsWith(text);

                  if (aStarts != bStarts) {
                    return aStarts ? -1 : 1;
                  }

                  return a.compareTo(b);
                });
              });
            }

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: SizedBox(
                width: 560,
                height: 620,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF102F46),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: TextField(
                        controller: searchController,
                        autofocus: true,
                        onChanged: filter,
                        decoration: InputDecoration(
                          hintText: searchHint,
                          prefixIcon: const Icon(Icons.search),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text(
                                'No matching result',
                                style: TextStyle(
                                  color: Color(0xFF71818A),
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: filtered.length,
                              separatorBuilder: (_, _) => const Divider(
                                height: 1,
                                indent: 18,
                                endIndent: 18,
                              ),
                              itemBuilder: (context, index) {
                                final item = filtered[index];

                                return ListTile(
                                  leading: const Icon(
                                    Icons.location_on_outlined,
                                    color: Color(0xFF0A8B86),
                                  ),
                                  title: Text(item),
                                  onTap: () {
                                    Navigator.pop(dialogContext, item);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    searchController.dispose();
    return result;
  }

  Future<void> _selectProvince() async {
    final province = await _pickFromList(
      title: 'Select province',
      values: _provinces,
      searchHint: 'Search province...',
    );

    if (province == null || !mounted) return;

    setState(() {
      if (_selectedProvince != province) {
        _cityController.clear();
      }

      _selectedProvince = province;
      _provinceController.text = province;
    });
  }

  Future<void> _selectCity() async {
    if (_selectedProvince == null) {
      _showMessage(
        'Select a province first.',
        error: true,
      );
      return;
    }

    final city = await _pickFromList(
      title: 'Select city - $_selectedProvince',
      values: _cities,
      searchHint: 'Search city...',
    );

    if (city == null || !mounted) return;

    setState(() {
      _cityController.text = city;
    });
  }

  Future<void> _openTerms() async {
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(30),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 760,
              maxHeight: 720,
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF2F9F8),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(26),
                    ),
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: Color(0xFFDDF2EF),
                        child: Icon(
                          Icons.gavel_outlined,
                          color: Color(0xFF087B76),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Clinical Use Terms & Disclaimer',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF102F46),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          Navigator.pop(dialogContext, false);
                        },
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(26),
                    child: Directionality(
                      textDirection: TextDirection.rtl,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: const [
                          Text(
                            'شرایط استفاده بالینی از Assistant Vet',
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF102F46),
                            ),
                          ),
                          SizedBox(height: 20),
                          _TermsItem(
                            number: '۱',
                            text:
                                'Assistant Vet یک ابزار کمک‌تصمیم‌گیری بالینی برای دامپزشکان است و جایگزین قضاوت حرفه‌ای، معاینه بیمار، تشخیص نهایی یا تصمیم درمانی دامپزشک نیست.',
                          ),
                          _TermsItem(
                            number: '۲',
                            text:
                                'تشخیص‌های احتمالی، تشخیص‌های افتراقی، پیشنهاد آزمایش، تفسیر نتایج و ملاحظات درمانی ارائه‌شده توسط برنامه باید توسط دامپزشک بررسی و با شرایط واقعی بیمار تطبیق داده شوند.',
                          ),
                          _TermsItem(
                            number: '۳',
                            text:
                                'مسئولیت تصمیم نهایی درباره تشخیص، انتخاب خط درمان، دوز دارو، تجویز، تغییر یا قطع درمان و پیگیری بیمار بر عهده دامپزشک استفاده‌کننده است.',
                          ),
                          _TermsItem(
                            number: '۴',
                            text:
                                'کاربر باید پیش از تصمیم‌گیری بالینی، مقالات، منابع، راهنماها و بخش‌های کتاب معرفی‌شده توسط برنامه را در صورت نیاز مطالعه و اعتبار آن‌ها را بررسی کند.',
                          ),
                          _TermsItem(
                            number: '۵',
                            text:
                                'خروجی هوش مصنوعی می‌تواند ناقص، نامطمئن یا در مواردی نادرست باشد. نبود یک یافته در خروجی برنامه به معنی رد قطعی آن نیست.',
                          ),
                          _TermsItem(
                            number: '۶',
                            text:
                                'در موارد اورژانسی یا بحرانی، استفاده از برنامه نباید باعث تأخیر در اقدامات استاندارد و ضروری دامپزشکی شود.',
                          ),
                          _TermsItem(
                            number: '۷',
                            text:
                                'Assistant Vet نقش دستیار علمی و تحلیلی دارد؛ تصمیم‌گیرنده نهایی و مسئول خط درمان، دامپزشک معالج است.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: Color(0xFFE4ECEC),
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(dialogContext, false);
                        },
                        child: const Text('I do not agree'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0AA7A0),
                        ),
                        onPressed: () {
                          Navigator.pop(dialogContext, true);
                        },
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('I have read and agree'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (accepted == true && mounted) {
      setState(() {
        _acceptedTerms = true;
      });
    }
  }

  String _friendlyAuthError(String message) {
    final lower = message.toLowerCase();

    if (lower.contains('already registered') ||
        lower.contains('already exists')) {
      return 'An account already exists with this email. Please sign in instead.';
    }

    if (lower.contains('rate limit') ||
        lower.contains('too many')) {
      return 'Too many attempts. Please wait and try again.';
    }

    return message;
  }

  Future<void> _createAccount() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedProvince == null) {
      _showMessage(
        'Select a province.',
        error: true,
      );
      return;
    }

    if (_cityController.text.trim().isEmpty) {
      _showMessage(
        'Select a city.',
        error: true,
      );
      return;
    }

    if (!_acceptedTerms) {
      await _openTerms();

      if (!_acceptedTerms) {
        return;
      }
    }

    final email = _emailController.text.trim();
    final mobile = _normalizeDigits(_mobileController.text);

    setState(() {
      _loading = true;
    });

    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: email,
        password: _passwordController.text,
        data: {
          'full_name': _fullNameController.text.trim(),
          'veterinary_council_code': _councilCodeController.text.trim(),
          'mobile': mobile,
          'mobile_e164': '+98${mobile.substring(1)}',
          'province': _selectedProvince,
          'city': _cityController.text.trim(),
          'clinic_name': _clinicController.text.trim(),
          'account_type': 'veterinarian',
          'professional_verification': 'pending',
          'clinical_disclaimer_accepted': true,
          'clinical_disclaimer_version': '2026-10-v2',
          'clinical_disclaimer_accepted_at':
              DateTime.now().toUtc().toIso8601String(),
        },
      );

      if (!mounted) return;

      final user = response.user;

      if (user == null) {
        _showMessage(
          'Could not create your account.',
          error: true,
        );
        return;
      }

      if (user.identities != null && user.identities!.isEmpty) {
        _showMessage(
          'An account already exists with this email. Please sign in instead.',
          error: true,
        );
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VerifyEmailPage(
            email: email,
          ),
        ),
      );
    } on AuthException catch (error) {
      if (!mounted) return;

      _showMessage(
        _friendlyAuthError(error.message),
        error: true,
      );
    } catch (_) {
      if (!mounted) return;

      _showMessage(
        'Something went wrong. Please check your internet connection.',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Widget _pickerField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      enabled: enabled,
      onTap: onTap,
      validator: _required,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        suffixIcon: const Icon(Icons.search),
      ),
    );
  }

  Widget _twoFields(Widget first, Widget second) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Column(
            children: [
              first,
              const SizedBox(height: 14),
              second,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 14),
            Expanded(child: second),
          ],
        );
      },
    );
  }

  Widget _sectionHeader(
    String title,
    String subtitle,
    IconData icon,
  ) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFE5F5F3),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(
            icon,
            color: const Color(0xFF087B76),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF102F46),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF7A8990),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _brandPanel() {
    return Container(
      width: 330,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF07596A),
            Color(0xFF087B76),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1C000000),
            blurRadius: 30,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 72,
            height: 72,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Image.asset(
              'assets/logo.png',
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Assistant Vet',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Professional veterinary access',
            style: TextStyle(
              color: Color(0xFFD9F2EF),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 28),
          const _BrandItem(
            icon: Icons.verified_user_outlined,
            title: 'Email verification',
            subtitle: 'Your email must be verified before access.',
          ),
          const _BrandItem(
            icon: Icons.badge_outlined,
            title: 'Professional profile',
            subtitle:
                'Veterinary professional information is stored with your account.',
          ),
          const _BrandItem(
            icon: Icons.shield_outlined,
            title: 'Clinician in control',
            subtitle:
                'Assistant Vet supports clinical decisions; it does not replace them.',
          ),
          const SizedBox(height: 22),
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: SizedBox(
              height: 180,
              width: double.infinity,
              child: Image.asset(
                'assets/dog_cat.png',
                fit: BoxFit.cover,
                alignment: Alignment.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _formCard() {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: const Color(0xFFE3ECEC),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 30,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Create your professional account',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: Color(0xFF102F46),
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'Enter your professional details. Email verification is required before entering the clinical workspace.',
              style: TextStyle(
                color: Color(0xFF71818A),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            _sectionHeader(
              'Professional information',
              'Basic information for your veterinary account.',
              Icons.badge_outlined,
            ),
            const SizedBox(height: 18),
            _twoFields(
              TextFormField(
                controller: _fullNameController,
                validator: _required,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              TextFormField(
                controller: _councilCodeController,
                validator: _required,
                decoration: const InputDecoration(
                  labelText: 'Veterinary Council Code',
                  prefixIcon: Icon(Icons.workspace_premium_outlined),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _twoFields(
              TextFormField(
                controller: _emailController,
                validator: _validateEmail,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              TextFormField(
                controller: _mobileController,
                validator: _validateMobile,
                keyboardType: TextInputType.phone,
                maxLength: 11,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'[0-9۰-۹٠-٩]'),
                  ),
                ],
                decoration: const InputDecoration(
                  labelText: 'Iranian mobile number',
                  hintText: '09xxxxxxxxx',
                  counterText: '',
                  prefixIcon: Icon(Icons.phone_iphone_outlined),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _twoFields(
              _pickerField(
                controller: _provinceController,
                label: 'Province',
                hint: 'Search province',
                icon: Icons.map_outlined,
                onTap: _selectProvince,
              ),
              _pickerField(
                controller: _cityController,
                label: 'City',
                hint: _selectedProvince == null
                    ? 'Select province first'
                    : 'Search city',
                icon: Icons.location_city_outlined,
                onTap: _selectCity,
                enabled: _selectedProvince != null,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Province and city are linked. Changing the province clears the previous city automatically.',
              style: TextStyle(
                color: Color(0xFF829097),
                fontSize: 11,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _clinicController,
              decoration: const InputDecoration(
                labelText: 'Clinic / Hospital name (optional)',
                prefixIcon: Icon(Icons.local_hospital_outlined),
              ),
            ),
            const SizedBox(height: 30),
            _sectionHeader(
              'Account security',
              'Use a strong password.',
              Icons.lock_outline,
            ),
            const SizedBox(height: 18),
            _twoFields(
              TextFormField(
                controller: _passwordController,
                obscureText: _hidePassword,
                validator: _validatePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        _hidePassword = !_hidePassword;
                      });
                    },
                    icon: Icon(
                      _hidePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _hideConfirmPassword,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Confirm your password';
                  }

                  if (value != _passwordController.text) {
                    return 'Passwords do not match';
                  }

                  return null;
                },
                decoration: InputDecoration(
                  labelText: 'Confirm password',
                  prefixIcon: const Icon(Icons.lock_reset_outlined),
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        _hideConfirmPassword = !_hideConfirmPassword;
                      });
                    },
                    icon: Icon(
                      _hideConfirmPassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 26),
            InkWell(
              onTap: _openTerms,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: _acceptedTerms
                      ? const Color(0xFFEAF7F4)
                      : const Color(0xFFF8FAFA),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _acceptedTerms
                        ? const Color(0xFF9ED8D0)
                        : const Color(0xFFDCE7E7),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: _acceptedTerms,
                      activeColor: const Color(0xFF0AA7A0),
                      onChanged: (_) {
                        if (_acceptedTerms) {
                          setState(() {
                            _acceptedTerms = false;
                          });
                        } else {
                          _openTerms();
                        }
                      },
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(top: 5),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Clinical Use Terms & Disclaimer',
                              style: TextStyle(
                                color: Color(0xFF102F46),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 5),
                            Text(
                              'Assistant Vet is a clinical decision-support tool. The veterinarian remains responsible for diagnosis and treatment decisions.',
                              style: TextStyle(
                                color: Color(0xFF667983),
                                fontSize: 12,
                                height: 1.45,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Click to read the full terms',
                              style: TextStyle(
                                color: Color(0xFF087B76),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0AA7A0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(17),
                  ),
                ),
                onPressed: _loading ? null : _createAccount,
                icon: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.mark_email_unread_outlined),
                label: Text(
                  _loading
                      ? 'Creating account...'
                      : 'Create account & send verification code',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: TextButton(
                onPressed: _loading
                    ? null
                    : () {
                        Navigator.pop(context);
                      },
                child: const Text(
                  'Already have an account? Sign in',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F7F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Create veterinary account',
          style: TextStyle(
            color: Color(0xFF102F46),
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 1050;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 1220,
                  ),
                  child: desktop
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _brandPanel(),
                            const SizedBox(width: 20),
                            Expanded(
                              child: _formCard(),
                            ),
                          ],
                        )
                      : _formCard(),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TermsItem extends StatelessWidget {
  final String number;
  final String text;

  const _TermsItem({
    required this.number,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFE5F5F3),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              number,
              style: const TextStyle(
                color: Color(0xFF087B76),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF405B68),
                height: 1.8,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _BrandItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFFD8EFED),
                    fontSize: 11,
                    height: 1.45,
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
