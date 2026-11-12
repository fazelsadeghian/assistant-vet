# Assistant Vet Brain v0.1

این اولین اسکلت واقعی مغز Assistant Vet است.

### الان چه چیزهایی دارد؟
- ورودی کیس سگ و گربه
- Rule Engine مستقل
- Knowledge Base محلی برای کتاب‌ها
- ورود PDF متنی و Chunking
- جست‌وجوی PubMed
- جست‌وجوی Europe PMC
- AI Provider قابل تعویض
- اتصال آماده به Ollama
- Clinical Reasoner
- Independent Reviewer
- Audit Trail
- Dockerfile برای انتقال بعدی روی سرور

### نکته مهم
این نسخه هنوز برای استفاده بالینی نهایی نیست.
دوز دارو، رفرنس‌اینترول‌ها، contraindicationها و قواعد درمان فقط بعد از ورود منابع معتبر و اعتبارسنجی اضافه می‌شوند.

### مسیر کلی
Case
→ Rule/QC
→ Veterinary Knowledge Base
→ PubMed / Europe PMC
→ Local AI Reasoner
→ Independent Reviewer
→ Structured Result
→ Veterinarian Confirmation
→ بعداً Drug/Price Engine + PDF

### مزیت اصلی
مدل AI به یک شرکت قفل نشده.
امروز Local/Ollama استفاده می‌کنیم.
بعداً Gemini، DeepSeek، OpenAI یا مدل‌های دیگر را بدون بازنویسی Flutter و Knowledge Base اضافه می‌کنیم.
