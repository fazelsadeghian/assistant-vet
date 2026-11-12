import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'repro_local_store.dart';
import 'repro_cycle_engine_v34.dart';
import 'repro_hormone_planner_v33.dart';
import 'repro_jalali_v35.dart';

const _dark=Color(0xFF12384C),_teal=Color(0xFF008E87),_grey=Color(0xFF6F858E);

/// A symbolic drawing of data entered by the veterinarian (not an ultrasound).
class OvaryDiagramV34 extends StatelessWidget{
  final String side;
  final double? follicle,clSize, hypothetical;
  final bool? cl;
  final int? chGrade;
  const OvaryDiagramV34({super.key,required this.side,this.follicle,this.cl,this.clSize,this.hypothetical,this.chGrade});
  @override Widget build(BuildContext context)=>Container(padding:const EdgeInsets.all(12),
    decoration:BoxDecoration(color:const Color(0xFFF1F7F8),borderRadius:BorderRadius.circular(17)),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(side,style:const TextStyle(color:_dark,fontWeight:FontWeight.w900)),
      SizedBox(height:130,width:double.infinity,child:CustomPaint(painter:_OvaryPaint(follicle,cl,chGrade))),
      Text('Follicle ${follicle?.toStringAsFixed(1)??'—'} mm · CL ${cl==null?'?':cl!?'yes':'no'}',style:const TextStyle(fontSize:12)),
      if(cl==true&&clSize!=null)Text('CL ${clSize!.toStringAsFixed(1)} mm',style:const TextStyle(fontSize:11)),
      if(chGrade != null && chGrade! > 0) Text('CH $chGrade · درج‌شده توسط دامپزشک', style:const TextStyle(fontSize:11, color:Color(0xFF9D522F))),
      if(hypothetical!=null)...[
        const SizedBox(height:5),
        Text('48h mathematical extension: ${hypothetical!.toStringAsFixed(1)} mm',
          style:const TextStyle(fontSize:11,color:Color(0xFF946720))),
        const Text('پیش‌بینی رشد/تخمک‌گذاری نیست؛ فقط امتداد عددی اندازه‌ها.',style:TextStyle(fontSize:10,color:_grey)),
      ],
    ]));
}
class _OvaryPaint extends CustomPainter{
  final double? mm;final bool? cl;final int? ch;
  _OvaryPaint(this.mm,this.cl,this.ch);
  @override void paint(Canvas c,Size s){
    final center=Offset(s.width/2,s.height/2),rx=math.min(130.0,s.width*.43),ry=s.height*.39;
    c.drawOval(Rect.fromCenter(center:center,width:rx*2,height:ry*2),Paint()..color=const Color(0xFFF0C8B7));
    c.drawOval(Rect.fromCenter(center:center,width:rx*2,height:ry*2),Paint()..color=const Color(0xFFBC827C)..style=PaintingStyle.stroke..strokeWidth=2);
    final f=center+Offset(-rx*.22,4),rad=mm==null?9.0:math.min(ry*.78,math.max(9.0,mm!*.69));
    c.drawCircle(f,rad,Paint()..color=const Color(0xFF8FD3E0));
    c.drawCircle(f,rad,Paint()..color=const Color(0xFF39879C)..style=PaintingStyle.stroke..strokeWidth=2);
    if(cl==true){c.drawCircle(center+Offset(rx*.49,-ry*.2),16,Paint()..color=const Color(0xFFFFD25A));}
    if(ch!=null && ch!>0){c.drawCircle(center+Offset(rx*.24,ry*.48),14,Paint()..color=const Color(0xFFEFA16A));}
    final p=TextPainter(text:TextSpan(text:mm==null?'?':mm!.toStringAsFixed(0),style:const TextStyle(fontSize:13,color:_dark,fontWeight:FontWeight.w800)),textDirection:TextDirection.ltr)..layout();
    p.paint(c,f-Offset(p.width/2,p.height/2));
  }
  @override bool shouldRepaint(_OvaryPaint old)=>old.mm!=mm||old.cl!=cl||old.ch!=ch;
}

Future<BreedingEvent?> recordEquineScanV34(BuildContext context,ReproLocalStore store) async{
  final ctrls={for(final k in ['left','right','leftClSize','rightClSize','edema','note']) k:TextEditingController()};
  bool? lc,rc; int? lch, rch; String cervix='not_assessed',fluid='not_assessed';
  int estrus=-1;bool sameL=false,sameR=false;DateTime at=DateTime.now();
  String image='';String error='';StateSetter? redraw;
  double? number(String k)=>reproDouble(ctrls[k]!.text);
  Widget input(String k,String label)=>TextField(controller:ctrls[k],
    onChanged:(_)=>redraw?.call((){}),
    keyboardType:const TextInputType.numberWithOptions(decimal:true),
    decoration:InputDecoration(labelText:label,isDense:true));
  Widget clField(String side,bool? current,ValueChanged<bool?> onChange)=>DropdownButtonFormField<String>(
    key:ValueKey('$side$current'),initialValue:current==null?'unknown':current?'yes':'no',
    decoration:InputDecoration(labelText:'$side CL'),isExpanded:true,
    items:const [DropdownMenuItem(value:'unknown',child:Text('Not assessed')),
      DropdownMenuItem(value:'yes',child:Text('Present')),
      DropdownMenuItem(value:'no',child:Text('Absent'))],
    onChanged:(v)=>onChange(v=='unknown'?null:v=='yes'));
  Widget chField(String side, int? current, ValueChanged<int?> onChanged) =>
    DropdownButtonFormField<int>(
      value: current ?? -1,
      decoration: InputDecoration(labelText: '$side CH / جسم خونریزی‌دهنده'),
      items: const [
        DropdownMenuItem(value: -1, child: Text('ارزیابی نشده')),
        DropdownMenuItem(value: 0, child: Text('مشاهده نشد')),
        DropdownMenuItem(value: 1, child: Text('CH 1 · ثبت مورفولوژی')),
        DropdownMenuItem(value: 2, child: Text('CH 2 · ثبت مورفولوژی')),
        DropdownMenuItem(value: 3, child: Text('CH 3 · ثبت مورفولوژی')),
      ], onChanged: (v) => onChanged(v == -1 ? null : v));
  final ok=await showDialog<bool>(context:context,barrierDismissible:false,
    builder:(_)=>StatefulBuilder(builder:(ctx,update){redraw=update;return AlertDialog(
      title:const Text('Reproductive ultrasound · سونوگرافی اختصاصی'),
      content:SizedBox(width:780,child:SingleChildScrollView(child:Column(
        crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
          const Text('هر تخمدان مستقل است. نامشخص را با «وجود ندارد» اشتباه نگیرید.',style:TextStyle(fontSize:12,color:_grey)),
          const SizedBox(height:9),
          OutlinedButton.icon(icon:const Icon(Icons.schedule),
            label: Text(ReproJalali.stamp(at)),
            onPressed: () async {
              final picked = await ReproJalali.pickDateTime(ctx, at);
              if (picked != null) update(() => at = picked);
            }),
          const SizedBox(height:13),
          LayoutBuilder(builder:(c,b)=>Wrap(spacing:14,runSpacing:14,children:[
            SizedBox(width:b.maxWidth>620?(b.maxWidth-14)/2:b.maxWidth,
              child:Column(children:[OvaryDiagramV34(side:'LEFT / چپ',follicle:number('left'),cl:lc,clSize:number('leftClSize'),chGrade:lch),
                input('left','Follicle mm'),const SizedBox(height:7),
                clField('Left',lc,(v)=>update(()=>lc=v)),
                if(lc==true)input('leftClSize','CL mm (optional)'),
                const SizedBox(height:7),chField('Left', lch, (v)=>update(()=>lch=v)),
                CheckboxListTile(dense:true,contentPadding:EdgeInsets.zero,value:sameL,
                  title:const Text('همان فولیکول سونوی قبلی تأیید شده',style:TextStyle(fontSize:11)),
                  onChanged:(v)=>update(()=>sameL=v??false))])),
            SizedBox(width:b.maxWidth>620?(b.maxWidth-14)/2:b.maxWidth,
              child:Column(children:[OvaryDiagramV34(side:'RIGHT / راست',follicle:number('right'),cl:rc,clSize:number('rightClSize'),chGrade:rch),
                input('right','Follicle mm'),const SizedBox(height:7),
                clField('Right',rc,(v)=>update(()=>rc=v)),
                if(rc==true)input('rightClSize','CL mm (optional)'),
                const SizedBox(height:7),chField('Right', rch, (v)=>update(()=>rch=v)),
                CheckboxListTile(dense:true,contentPadding:EdgeInsets.zero,value:sameR,
                  title:const Text('همان فولیکول سونوی قبلی تأیید شده',style:TextStyle(fontSize:11)),
                  onChanged:(v)=>update(()=>sameR=v??false))])),
          ])),
          const SizedBox(height:10),
          const Text('نمای رحم · ادم ثبت‌شده توسط دامپزشک', style:TextStyle(fontWeight:FontWeight.bold)),
          UterusEdemaDiagramV35(edema: int.tryParse(ctrls['edema']!.text)),
          const Divider(height:23),
          Wrap(spacing:12,runSpacing:12,children:[
            SizedBox(width:160,child:input('edema','Uterine edema 0–5')),
            SizedBox(width:165,child:DropdownButtonFormField<int>(
              initialValue:estrus,decoration:const InputDecoration(labelText:'Estrus 0–4'),
              items:[for(final x in [-1,0,1,2,3,4]) DropdownMenuItem(value:x,
                child:Text(x<0?'Not assessed':'$x'))],onChanged:(v)=>update(()=>estrus=v??-1))),
            SizedBox(width:190,child:DropdownButtonFormField<String>(
              initialValue:cervix,decoration:const InputDecoration(labelText:'Cervix'),
              items:const [DropdownMenuItem(value:'not_assessed',child:Text('Not assessed')),
                DropdownMenuItem(value:'open',child:Text('Open')),
                DropdownMenuItem(value:'relaxed',child:Text('Relaxed')),
                DropdownMenuItem(value:'closed',child:Text('Closed'))],
              onChanged:(v)=>update(()=>cervix=v??'not_assessed'))),
            SizedBox(width:190,child:DropdownButtonFormField<String>(
              initialValue:fluid,decoration:const InputDecoration(labelText:'Uterine fluid'),
              items:const [DropdownMenuItem(value:'not_assessed',child:Text('Not assessed')),
                DropdownMenuItem(value:'absent',child:Text('Absent')),
                DropdownMenuItem(value:'present',child:Text('Present'))],
              onChanged:(v)=>update(()=>fluid=v??'not_assessed'))),
          ]),
          const SizedBox(height:9),
          TextField(controller:ctrls['note'],maxLines:2,decoration:const InputDecoration(labelText:'Other findings, uterine fluid depth and notes')),
          OutlinedButton.icon(onPressed:()async{
            final picked=await store.selectImage();if(picked!=null)update(()=>image=picked);
          },icon:const Icon(Icons.add_photo_alternate_outlined),label:Text(image.isEmpty?'Attach ultrasound':'Image selected')),
          if(error.isNotEmpty)Text(error,style:const TextStyle(color:Colors.red)),
        ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
        FilledButton(onPressed:(){
          for(final k in ['left','right','leftClSize','rightClSize']){
            final s=ctrls[k]!.text.trim(),n=number(k);
            if(s.isNotEmpty&&(n==null||n<=0||n>150)){update(()=>error='$k must be a positive number in mm');return;}
          }
          if(number('left')==null&&number('right')==null&&lc==null&&rc==null&&lch==null&&rch==null){
            update(()=>error='Record at least one ovarian finding');return;
          }
          final e=ctrls['edema']!.text.trim();final ed=int.tryParse(e);
          if(e.isNotEmpty&&(ed==null||ed<0||ed>5)){update(()=>error='Edema score must be 0–5');return;}
          Navigator.pop(ctx,true);
        },child:const Text('Save exam'))],
    );}));
  try{
    if(ok!=true)return null;
    return BreedingEvent(id:newReproId(),at:at,type:'ultrasound',
      leftFollicleMm:number('left'),rightFollicleMm:number('right'),
      leftCl:lc,rightCl:rc,leftClMm:number('leftClSize'),rightClMm:number('rightClSize'),
      leftChGrade:lch,rightChGrade:rch,
      sameLeftFollicle:sameL,sameRightFollicle:sameR,
      corpusLuteum:lc==true||rc==true?'present':lc==false&&rc==false?'absent':'not_assessed',
      cervixStatus:cervix,uterineFluid:fluid,
      edemaScore:int.tryParse(ctrls['edema']!.text.trim()),estrusScore:estrus<0?null:estrus,
      imagePath:image.isEmpty?'':await store.importImage(image),details:ctrls['note']!.text.trim());
  }finally{for(final c in ctrls.values){c.dispose();}}
}

class DynamicMareTimelineV34 extends StatelessWidget{
  final BreedingCycle cycle;final CycleReviewV34 review;final ReproScenarioResult scenario;
  final ValueChanged<DateTime> onAdd;
  const DynamicMareTimelineV34({super.key,required this.cycle,required this.review,
    required this.scenario,required this.onAdd});
  @override Widget build(BuildContext ctx){
    final scans=cycle.events.where((e)=>e.type=='ultrasound'&&!e.plannedByVet).toList()..sort((a,b)=>a.at.compareTo(b.at));
    final anchor=cycle.heatStart??(scans.isEmpty?DateTime.now():scans.first.at);
    final start=DateTime(anchor.year,anchor.month,anchor.day);
    final now=DateTime.now(),days=cycle.cycleDisplayDays;
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('نما از ${cycle.heatStart==null?'اولین سونو':'شروع فحلی'}؛ روزهای نمایشی، روز قطعی پس از تخمک‌گذاری نیستند.',
        style:const TextStyle(fontSize:11,color:_grey)),
      const SizedBox(height:8),
      SizedBox(height:138,child:ListView.separated(scrollDirection:Axis.horizontal,itemCount:days,
        separatorBuilder:(_,__)=>const SizedBox(width:5),itemBuilder:(ctx,i){
          final at=start.add(Duration(days:i)),end=at.add(const Duration(days:1));
          final es=cycle.events.where((e)=>!e.at.isBefore(at)&&e.at.isBefore(end)).toList();
          final ws=scenario.windows.where((w)=>w.start.isBefore(end)&&w.end.isAfter(at)).toList();
          final today=at.year==now.year&&at.month==now.month&&at.day==now.day;
          return InkWell(onTap:()=>onAdd(DateTime(at.year,at.month,at.day,9)),
            child:Container(width:95,padding:const EdgeInsets.all(8),decoration:BoxDecoration(
              color:today?const Color(0xFFDFF3EF):const Color(0xFFF2F6F7),
              border:Border.all(color:today?_teal:const Color(0xFFDFE9EA)),borderRadius:BorderRadius.circular(11)),
              child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text('Day ${i+1}',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:12)),
                Text('${at.month}/${at.day}',style:const TextStyle(color:_grey,fontSize:10)),
                for(final e in es.take(2))Container(margin:const EdgeInsets.only(top:4),padding:const EdgeInsets.all(3),
                  decoration:BoxDecoration(color:e.plannedByVet?Colors.white:const Color(0xFFC8E5E9),
                    borderRadius:BorderRadius.circular(5)),
                  child:Text('${e.type} ${e.at.hour}:${e.at.minute.toString().padLeft(2,'0')}',
                    maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:9))),
                const Spacer(),
                if(ws.isNotEmpty)Container(height:8,decoration:BoxDecoration(color:const Color(0xFF39B5A8),
                  borderRadius:BorderRadius.circular(5))),
                const Text('+ add',style:TextStyle(fontSize:9,color:_teal)),
              ])));
        })),
      const SizedBox(height:8),
      for(final w in scenario.windows)Text('${w.label}: ${w.start.month}/${w.start.day} ${w.start.hour}:00 – ${w.end.month}/${w.end.day} ${w.end.hour}:00',
        style:const TextStyle(fontSize:11,color:_dark)),
      const Text('تیره: رویداد ثبت‌شده · سفید: نوبت دامپزشک · سبز: سناریوی فرضی. هیچ سناریویی خودکار ثبت نمی‌شود.',
        style:TextStyle(fontSize:10,color:_grey)),
    ]);
  }
}

class EquineWordSearchV34 extends StatefulWidget{
  final String summary;
  const EquineWordSearchV34({super.key,required this.summary});
  @override State<EquineWordSearchV34> createState()=>_WordState();
}
class _WordState extends State<EquineWordSearchV34>{
  final controller=TextEditingController();
  List<dynamic> blocks=[],hits=[];
  String status='Loading full clinical Word…',ai='';bool busy=false;
  @override void initState(){super.initState();_load();}
  Future<void> _load()async{try{
    final raw=await rootBundle.loadString('assets/equine_knowledge_v34.json');
    final data=jsonDecode(raw) as Map<String,dynamic>;
    if(mounted)setState((){blocks=data['blocks'] as List;status='${blocks.length} بخش شامل ۳۶ جدول قابل جست‌وجو است';});
  }catch(e){if(mounted)setState(()=>status='Load error: $e');}}
  void _search(){
    final query=controller.text.toLowerCase().trim().split(RegExp(r'\s+')).where((x)=>x.length>=2).toList();
    if(query.isEmpty)return;
    final results=<dynamic>[];
    for(final b in blocks){final t=('${b['section']} ${b['text']}').toLowerCase();
      if(query.any(t.contains)){results.add(b);if(results.length>=25)break;}}
    setState(()=>hits=results);
  }
  Future<void> _askAI()async{
    if(controller.text.trim().length<4)return;
    setState((){busy=true;ai='';});
    HttpClient? client;
    try{
      client=HttpClient()..connectionTimeout=const Duration(seconds:5);
      final r=await client.postUrl(Uri.parse('http://127.0.0.1:8000/equine/v34/explain'));
      r.headers.contentType=ContentType.json;r.write(jsonEncode({'question':controller.text.trim(),
        'clinical_summary':widget.summary,'limit':6}));
      final response=await r.close().timeout(const Duration(seconds:120));
      final data=jsonDecode(await utf8.decoder.bind(response).join());
      if(mounted)setState(()=>ai='${data['answer']??'No response'}\nStatus: ${data['status']}');
    }catch(e){if(mounted)setState(()=>ai='Backend v34 هنوز متصل نیست. جست‌وجوی کامل Word آفلاین کار می‌کند. $e');}
    finally{client?.close();if(mounted)setState(()=>busy=false);}
  }
  @override void dispose(){controller.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text('Full Word Evidence · $status',style:const TextStyle(fontSize:12,color:_grey)),
    const SizedBox(height:8),
    Row(children:[Expanded(child:TextField(controller:controller,onSubmitted:(_)=>_search(),
      decoration:const InputDecoration(hintText:'جست‌وجو: PGF2, follicle, frozen...',isDense:true))),
      const SizedBox(width:8),FilledButton(onPressed:_search,child:const Text('Search')),
      const SizedBox(width:7),OutlinedButton(onPressed:busy?null:_askAI,
        child:Text(busy?'…':'Ask AI'))]),
    if(ai.isNotEmpty)Padding(padding:const EdgeInsets.all(9),child:SelectableText(ai)),
    if(hits.isNotEmpty)SizedBox(height:230,child:ListView.builder(itemCount:hits.length,
      itemBuilder:(ctx,i){final b=hits[i];return ExpansionTile(dense:true,
        title:Text('[${b['id']}] ${b['section']}',maxLines:1,overflow:TextOverflow.ellipsis,
          style:const TextStyle(fontSize:12)),
        children:[Padding(padding:const EdgeInsets.all(12),child:SelectableText('${b['text']}',
          style:const TextStyle(fontSize:12,height:1.5)))]);
      })),
    const Text('متن سند به معنی دستور درمان تأییدشده نیست. پاسخ AI نیازمند بازبینی متخصص است.',
      style:TextStyle(fontSize:10,color:_grey)),
  ]);
}

/// Uterine horns and body, schematic only. Stronger teal curves represent a
/// greater *recorded* edema score. This is never a reconstructed ultrasound.
class UterusEdemaDiagramV35 extends StatelessWidget {
  final int? edema;
  const UterusEdemaDiagramV35({super.key, this.edema});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: const Color(0xFFF1F7F8),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFDCE8E9)),
    ),
    child: Column(children: [
      SizedBox(height: 100, width: double.infinity,
        child: CustomPaint(painter: _UterusPaintV35(edema))),
      Text('رحم · ادم: ${edema == null ? 'ارزیابی نشده' : '$edema / 5'}',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      const Text('شماتیک آموزشی؛ شدت ادم همان امتیاز ثبت‌شده در سونو است.',
        style: TextStyle(fontSize: 10, color: Color(0xFF6F858E))),
    ]),
  );
}

class _UterusPaintV35 extends CustomPainter {
  final int? edema;
  const _UterusPaintV35(this.edema);
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, h = size.height;
    final shell = Paint()..color = const Color(0xFFE7B5AE)
      ..strokeWidth = 13..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final outline = Paint()..color = const Color(0xFF9C6A69)
      ..strokeWidth = 1.6..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final horn = Path()
      ..moveTo(cx, h * .78)
      ..lineTo(cx, h * .45)
      ..quadraticBezierTo(cx - 8, h * .37, cx - 24, h * .35)
      ..quadraticBezierTo(cx - 48, h * .34, cx - 75, h * .17)
      ..moveTo(cx, h * .45)
      ..quadraticBezierTo(cx + 8, h * .37, cx + 24, h * .35)
      ..quadraticBezierTo(cx + 48, h * .34, cx + 75, h * .17);
    canvas.drawPath(horn, shell);
    canvas.drawPath(horn, outline);
    if (edema != null && edema! > 0) {
      final marker = Paint()..color = const Color(0xFF078E94)
        ..strokeWidth = 1.3 + edema! * .36..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < edema!.clamp(0, 5); i++) {
        final y = h * (.38 + i * .065);
        canvas.drawArc(Rect.fromCenter(center: Offset(cx, y),
            width: 28 + i * 3, height: 10), 0.1, 3.0, false, marker);
      }
    }
  }
  @override
  bool shouldRepaint(_UterusPaintV35 old) => old.edema != edema;
}
