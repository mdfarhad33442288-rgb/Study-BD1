import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/strings.dart';
import '../../core/providers.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/common.dart';

class PaymentArgs {
  final String type; // premium | course | donation
  final String refId;
  final String title;
  final double amount;
  final int days; // for premium
  final bool amountEditable;
  const PaymentArgs({required this.type, this.refId = '', required this.title, this.amount = 0, this.days = 0, this.amountEditable = false});
}

const _defaultPlans = [
  {'id': 'monthly', 'nameEn': 'Monthly', 'nameBn': 'মাসিক', 'days': 30, 'price': 99},
  {'id': 'yearly', 'nameEn': 'Yearly (best value)', 'nameBn': 'বার্ষিক (সাশ্রয়ী)', 'days': 365, 'price': 799},
];

class PremiumScreen extends ConsumerWidget {
  const PremiumScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = context.lang;
    final user = ref.watch(appUserProvider).valueOrNull;
    final cfg = ref.watch(remoteConfigProvider).valueOrNull ?? {};
    final plans = ((cfg['plans'] as List?) ?? _defaultPlans).cast<Map>();
    final benefits = lang == 'bn'
        ? ['বিজ্ঞাপনমুক্ত অভিজ্ঞতা', 'আনলিমিটেড ডাউনলোড', 'প্রিমিয়াম কোর্স', 'প্রিমিয়াম নোটস', 'প্রিমিয়াম মক টেস্ট', 'এআই টিউটরের বেশি সীমা']
        : ['Remove ads', 'Unlimited downloads', 'Premium courses', 'Premium notes', 'Premium mock tests', 'Higher AI tutor limits'];

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('premium'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (user?.isPremium ?? false)
          Card(color: Theme.of(context).colorScheme.primaryContainer, child: ListTile(leading: const Icon(Icons.workspace_premium), title: Text(lang == 'bn' ? 'আপনি প্রিমিয়াম সদস্য' : 'You are a Premium member'), subtitle: user?.premiumUntil == null ? null : Text('Until ${user!.premiumUntil.toString().substring(0, 10)}'))),
        const SizedBox(height: 8),
        for (final b in benefits) ListTile(dense: true, leading: const Icon(Icons.check_circle, color: Colors.green), title: Text(b)),
        const Divider(height: 32),
        for (final p in plans)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              title: Text(lang == 'bn' ? '${p['nameBn']}' : '${p['nameEn']}'),
              subtitle: Text('${p['days']} days'),
              trailing: Text('৳${p['price']}', style: Theme.of(context).textTheme.titleLarge),
              onTap: () => context.push('/pay', extra: PaymentArgs(type: 'premium', refId: '${p['id']}', title: 'Premium – ${p['nameEn']}', amount: (p['price'] as num).toDouble(), days: (p['days'] as num).toInt())),
            ),
          ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: () => context.push('/pay', extra: const PaymentArgs(type: 'donation', title: 'Donation', amountEditable: true)),
          icon: const Icon(Icons.volunteer_activism),
          label: Text(lang == 'bn' ? 'অনুদান দিন' : 'Donate to support free education'),
        ),
      ]),
    );
  }
}

/// Manual mobile-banking payment (bKash / Nagad / Rocket): the user sends money,
/// submits the transaction ID, and an admin approves it in the admin panel.
/// Approval unlocks premium / the course automatically.
class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key, required this.args});
  final PaymentArgs args;
  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  final _trx = TextEditingController();
  final _sender = TextEditingController();
  late final _amount = TextEditingController(text: widget.args.amount > 0 ? widget.args.amount.toStringAsFixed(0) : '');
  String _method = 'bkash';
  bool _busy = false;

  Future<void> _submit() async {
    final amount = double.tryParse(_amount.text) ?? 0;
    if (_trx.text.trim().length < 6 || amount <= 0) {
      snack(context, 'Enter a valid amount and transaction ID');
      return;
    }
    if (Validators.bdPhone(_sender.text) != null) {
      snack(context, 'Enter the mobile number you paid from (01XXXXXXXXX)');
      return;
    }
    setState(() => _busy = true);
    try {
      final u = ref.read(authStateProvider).valueOrNull!;
      final name = ref.read(appUserProvider).valueOrNull?.name ?? '';
      await FirebaseFirestore.instance.collection('payments').add({
        'uid': u.uid,
        'userName': name,
        'type': widget.args.type,
        'refId': widget.args.refId,
        'title': widget.args.title,
        'days': widget.args.days,
        'amount': amount,
        'method': _method,
        'trxId': _trx.text.trim(),
        'senderNumber': _sender.text.trim(),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      snack(context, 'Submitted. We will verify and activate shortly.');
      context.pop();
    } catch (e) {
      if (mounted) snack(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(remoteConfigProvider).valueOrNull ?? {};
    final pay = Map<String, dynamic>.from(cfg['payment'] ?? {});
    final number = (pay[_method] ?? '').toString();
    final uid = ref.watch(authStateProvider).valueOrNull?.uid;

    return Scaffold(
      appBar: AppBar(title: Text(widget.args.title)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Dropdown<String>(label: 'Payment method', value: _method, items: const {'bkash': 'bKash', 'nagad': 'Nagad', 'rocket': 'Rocket'}, onChanged: (v) => setState(() => _method = v!)),
        Card(
          child: ListTile(
            title: Text(number.isEmpty ? 'Payment number not configured yet' : 'Send money to: $number'),
            subtitle: Text((pay['note'] ?? 'Use “Send Money”, then enter the transaction ID below.').toString()),
            trailing: number.isEmpty ? null : IconButton(icon: const Icon(Icons.copy), onPressed: () => Clipboard.setData(ClipboardData(text: number))),
          ),
        ),
        const SizedBox(height: 12),
        if (widget.args.amountEditable || widget.args.amount == 0) Field('Amount (৳)', _amount, keyboard: TextInputType.number) else Text('Amount: ৳${widget.args.amount.toStringAsFixed(0)}', style: Theme.of(context).textTheme.titleMedium),
        Field('Your ${_method == 'bkash' ? 'bKash' : _method} number', _sender, keyboard: TextInputType.phone),
        Field('Transaction ID (TrxID)', _trx),
        FilledButton(onPressed: _busy ? null : _submit, child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(context.tr('submit'))),
        const SizedBox(height: 24),
        if (uid != null) ...[
          Text('My payments', style: Theme.of(context).textTheme.titleMedium),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('payments').where('uid', isEqualTo: uid).snapshots(),
            builder: (_, s) => Column(children: [
              for (final d in (s.data?.docs ?? [])) ListTile(dense: true, title: Text('${d['title']}'), subtitle: Text('${d['trxId']}'), trailing: Chip(label: Text('${d['status']}'))),
            ]),
          ),
        ],
      ]),
    );
  }
}
