import 'package:flutter/material.dart';

/// A content category inside a section (e.g. "NCTB Book", "MCQ").
class Cat {
  final String id, en, bn;
  final IconData icon;
  const Cat(this.id, this.en, this.bn, this.icon);
  String name(String lang) => lang == 'bn' ? bn : en;
}

/// A group inside a section (e.g. "Class 7", "Medical Admission").
class Group {
  final String id, en, bn;
  const Group(this.id, this.en, this.bn);
  String name(String lang) => lang == 'bn' ? bn : en;
}

class SectionDef {
  final String id, en, bn;
  final IconData icon;
  final Color color;
  final List<Group> groups;
  final List<Cat> cats;
  SectionDef(this.id, this.en, this.bn, this.icon, this.color,
      {this.groups = const [], required this.cats});
  bool get hasGroups => groups.isNotEmpty;
  String name(String lang) => lang == 'bn' ? bn : en;
}

class Sections {
  static const _bnDigits = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
  static String bnNum(int n) => n.toString().split('').map((c) => _bnDigits[int.parse(c)]).join();

  static final academic = SectionDef(
    'academic', 'Academic', 'একাডেমিক', Icons.school, const Color(0xFF0B7A4B),
    groups: List.generate(12, (i) => Group('${i + 1}', 'Class ${i + 1}', 'ক্লাস ${bnNum(i + 1)}')),
    cats: const [
      Cat('nctb', 'NCTB Books', 'এনসিটিবি বই', Icons.menu_book),
      Cat('guide', 'Guide Books', 'গাইড বই', Icons.auto_stories),
      Cat('testpaper', 'Test Papers', 'টেস্ট পেপার', Icons.description),
      Cat('notes', 'Notes', 'নোটস', Icons.note_alt),
      Cat('suggestion', 'Suggestions', 'সাজেশন', Icons.lightbulb),
      Cat('creative', 'Creative Questions', 'সৃজনশীল প্রশ্ন', Icons.psychology),
      Cat('mcq', 'MCQ', 'বহুনির্বাচনী (MCQ)', Icons.checklist),
      Cat('cq', 'CQ', 'সৃজনশীল (CQ)', Icons.edit_note),
      Cat('previous', 'Previous Year Questions', 'পূর্ববর্তী বছরের প্রশ্ন', Icons.history_edu),
      Cat('model', 'Model Test', 'মডেল টেস্ট', Icons.quiz),
      Cat('board', 'Board Questions', 'বোর্ড প্রশ্ন', Icons.account_balance),
      Cat('answer', 'Answer Sheet', 'উত্তরপত্র', Icons.fact_check),
      Cat('video', 'Video Lessons', 'ভিডিও লেসন', Icons.play_circle),
      Cat('image', 'Images', 'ছবি', Icons.image),
    ],
  );

  static const _admissionCats = [
    Cat('book', 'Books', 'বই', Icons.menu_book),
    Cat('notes', 'Notes', 'নোটস', Icons.note_alt),
    Cat('mcq', 'MCQ', 'MCQ', Icons.checklist),
    Cat('mock', 'Mock Tests', 'মক টেস্ট', Icons.quiz),
    Cat('video', 'Video Classes', 'ভিডিও ক্লাস', Icons.play_circle),
    Cat('previous', 'Previous Questions', 'পূর্ববর্তী প্রশ্ন', Icons.history_edu),
  ];

  static final admission = SectionDef(
    'admission', 'Admission & Jobs', 'ভর্তি ও চাকরি', Icons.workspace_premium, const Color(0xFF6A1B9A),
    groups: const [
      Group('university', 'University Admission', 'বিশ্ববিদ্যালয় ভর্তি'),
      Group('medical', 'Medical Admission', 'মেডিকেল ভর্তি'),
      Group('engineering', 'Engineering Admission', 'ইঞ্জিনিয়ারিং ভর্তি'),
      Group('polytechnic', 'Polytechnic', 'পলিটেকনিক'),
      Group('nursing', 'Nursing', 'নার্সিং'),
      Group('bcs', 'BCS Preparation', 'বিসিএস প্রস্তুতি'),
      Group('bank', 'Bank Job Preparation', 'ব্যাংক জব প্রস্তুতি'),
      Group('govt', 'Government Job Preparation', 'সরকারি চাকরি প্রস্তুতি'),
      Group('primary', 'Primary Teacher Preparation', 'প্রাথমিক শিক্ষক প্রস্তুতি'),
    ],
    cats: _admissionCats,
  );

  static final english = SectionDef(
    'english', 'English Learning', 'ইংরেজি শিখুন', Icons.translate, const Color(0xFF1565C0),
    cats: const [
      Cat('spoken', 'Spoken English', 'স্পোকেন ইংলিশ', Icons.record_voice_over),
      Cat('conversation', 'Daily Conversation', 'দৈনন্দিন কথোপকথন', Icons.forum),
      Cat('grammar', 'Grammar', 'গ্রামার', Icons.spellcheck),
      Cat('vocabulary', 'Vocabulary', 'ভোকাবুলারি', Icons.abc),
      Cat('pronunciation', 'Pronunciation', 'উচ্চারণ', Icons.hearing),
      Cat('listening', 'Listening Practice', 'লিসেনিং প্র্যাকটিস', Icons.headphones),
      Cat('speaking', 'Speaking Practice', 'স্পিকিং প্র্যাকটিস', Icons.mic),
      Cat('translation', 'Translation Practice', 'অনুবাদ অনুশীলন', Icons.g_translate),
    ],
  );

  static final ielts = SectionDef(
    'ielts', 'IELTS', 'আইইএলটিএস', Icons.language, const Color(0xFFC62828),
    cats: const [
      Cat('reading', 'Reading', 'রিডিং', Icons.chrome_reader_mode),
      Cat('writing', 'Writing', 'রাইটিং', Icons.edit),
      Cat('listening', 'Listening', 'লিসেনিং', Icons.headphones),
      Cat('speaking', 'Speaking', 'স্পিকিং', Icons.mic),
      Cat('grammar', 'Grammar', 'গ্রামার', Icons.spellcheck),
      Cat('vocabulary', 'Vocabulary', 'ভোকাবুলারি', Icons.abc),
      Cat('mock', 'Mock Test', 'মক টেস্ট', Icons.quiz),
      Cat('practice', 'Practice Tests', 'প্র্যাকটিস টেস্ট', Icons.assignment),
      Cat('pdf', 'PDF', 'পিডিএফ', Icons.picture_as_pdf),
      Cat('video', 'Videos', 'ভিডিও', Icons.play_circle),
    ],
  );

  static final library = SectionDef(
    'library', 'Digital Library', 'ডিজিটাল লাইব্রেরি', Icons.local_library, const Color(0xFF4E342E),
    cats: const [
      Cat('books', 'Books', 'বই', Icons.menu_book),
      Cat('pdfs', 'PDFs', 'পিডিএফ', Icons.picture_as_pdf),
      Cat('notes', 'Notes', 'নোটস', Icons.note_alt),
      Cat('magazines', 'Magazines', 'ম্যাগাজিন', Icons.import_contacts),
      Cat('newspapers', 'Newspapers', 'পত্রিকা', Icons.newspaper),
      Cat('journals', 'Journals', 'জার্নাল', Icons.article),
    ],
  );

  static final video = SectionDef(
    'video', 'Video Learning', 'ভিডিও লার্নিং', Icons.smart_display, const Color(0xFFEF6C00),
    cats: const [
      Cat('youtube', 'YouTube Videos', 'ইউটিউব ভিডিও', Icons.smart_display),
      Cat('uploaded', 'Uploaded Videos', 'আপলোড করা ভিডিও', Icons.video_library),
      Cat('short', 'Short Lessons', 'শর্ট লেসন', Icons.timer),
      Cat('full', 'Full Courses', 'ফুল কোর্স', Icons.ondemand_video),
      Cat('playlist', 'Playlists', 'প্লেলিস্ট', Icons.playlist_play),
    ],
  );

  static final career = SectionDef(
    'career', 'Career', 'ক্যারিয়ার', Icons.work, const Color(0xFF00838F),
    cats: const [
      Cat('govt', 'Government Jobs', 'সরকারি চাকরি', Icons.account_balance),
      Cat('private', 'Private Jobs', 'বেসরকারি চাকরি', Icons.business),
      Cat('ngo', 'NGO Jobs', 'এনজিও চাকরি', Icons.volunteer_activism),
      Cat('freelancing', 'Freelancing', 'ফ্রিল্যান্সিং', Icons.laptop_mac),
      Cat('skill', 'Skill Development', 'দক্ষতা উন্নয়ন', Icons.build),
      Cat('scholarship', 'Scholarship', 'বৃত্তি', Icons.card_giftcard),
      Cat('internship', 'Internship', 'ইন্টার্নশিপ', Icons.badge),
      Cat('tips', 'Career Tips', 'ক্যারিয়ার টিপস', Icons.tips_and_updates),
    ],
  );

  static final news = SectionDef(
    'news', 'Education News', 'শিক্ষা সংবাদ', Icons.campaign, const Color(0xFF37474F),
    cats: const [
      Cat('news', 'Education News', 'শিক্ষা সংবাদ', Icons.newspaper),
      Cat('result', 'Result Updates', 'ফলাফল আপডেট', Icons.emoji_events),
      Cat('circular', 'Circular', 'সার্কুলার', Icons.assignment_late),
      Cat('notice', 'Notice Board', 'নোটিশ বোর্ড', Icons.push_pin),
      Cat('admission', 'Admission Notice', 'ভর্তি বিজ্ঞপ্তি', Icons.how_to_reg),
    ],
  );

  static final all = <SectionDef>[academic, admission, english, ielts, library, video, career, news];

  static SectionDef byId(String id) => all.firstWhere((s) => s.id == id);
}

/// Allowed content "kinds" an admin can upload.
const contentKinds = ['pdf', 'video', 'youtube', 'image', 'link', 'text'];
