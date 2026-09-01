import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // تهيئة قواعد البيانات المحلية في الهاتف
  await Hive.initFlutter();
  await Hive.openBox('daily_transactions'); // صندوق الحركات اليومية
  await Hive.openBox('daily_balances');     // صندوق أصدة الإغلاق لكل يوم

  runApp(const CashierApp());
}

class CashierApp extends StatelessWidget {
  const CashierApp({Super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'حركة الصندوق اليومية',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const CashierHomeScreen(),
    );
  }
}

class CashierHomeScreen extends StatefulWidget {
  const CashierHomeScreen({Super.key});

  @override
  State<CashierHomeScreen> createState() => _CashierHomeScreenState();
}

class _CashierHomeScreenState extends State<CashierHomeScreen> {
  final Box _transBox = Hive.getBox('daily_transactions');
  final Box _balanceBox = Hive.getBox('daily_balances');

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _detailsController = TextEditingController();

  String _selectedType = 'مقبوضات';
  late String _todayDate;

  @override
  void initState() {
    super.initState();
    _todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
  }

  // جلب حركات اليوم الحالي
  List<Map<String, dynamic>> _getTodayTransactions() {
    final List list = _transBox.get(_todayDate, defaultValue: []);
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // احتساب رصيد اليوم السابق تلقائياً من آخر يوم مسجل
  double _getAutoPreviousBalance() {
    final allKeys = _balanceBox.keys.toList()..sort();
    final previousKeys = allKeys.where((key) => key.toString().compareTo(_todayDate) < 0).toList();

    if (previousKeys.isNotEmpty) {
      return _balanceBox.get(previousKeys.last, defaultValue: 0.0);
    }
    return 0.0;
  }

  // إضافة حركة جديدة
  void _addTransaction() {
    final String details = _detailsController.text;
    final double? amount = double.tryParse(_amountController.text);

    if (details.isEmpty || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال مبلغ وبيان صحيحين')),
      );
      return;
    }

    final currentList = _getTodayTransactions();
    currentList.add({
      'type': _selectedType,
      'amount': amount,
      'details': details,
      'time': DateFormat('HH:mm').format(DateTime.now()),
    });

    _transBox.put(_todayDate, currentList);
    _updateTodayClosingBalance();

    _amountController.clear();
    _detailsController.clear();
    setState(() {});
  }

  // تحديث وحفظ رصيد الإغلاق لليوم
  void _updateTodayClosingBalance() {
    final transactions = _getTodayTransactions();
    double totalIncome = transactions.where((e) => e['type'] == 'مقبوضات').fold(0.0, (sum, i) => sum + i['amount']);
    double totalExpense = transactions.where((e) => e['type'] == 'مصروفات').fold(0.0, (sum, i) => sum + i['amount']);
    double prevBalance = _getAutoPreviousBalance();
    
    double finalBalance = (totalIncome + prevBalance) - totalExpense;
    _balanceBox.put(_todayDate, finalBalance);
  }

  // تصدير التقرير إلى PDF مطابِق للنماذج المرفقة
  Future<void> _exportPDF() async {
    final pdf = pw.Document();
    final transactions = _getTodayTransactions();

    final incomeList = transactions.where((e) => e['type'] == 'مقبوضات').toList();
    final expenseList = transactions.where((e) => e['type'] == 'مصروفات').toList();

    double totalIncome = incomeList.fold(0.0, (sum, item) => sum + item['amount']);
    double totalExpense = expenseList.fold(0.0, (sum, item) => sum + item['amount']);
    double prevBalance = _getAutoPreviousBalance();
    double grandTotal = totalIncome + prevBalance;
    double finalBalance = grandTotal - totalExpense;

    final arabicFont = await PdfGoogleFonts.cairoRegular();
    final arabicBoldFont = await PdfGoogleFonts.cairoBold();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicBoldFont),
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Padding(
              padding: const pw.EdgeInsets.all(15),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAlignment.stretch,
                children: [
                  pw.Center(child: pw.Text('حركة الصندوق', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold))),
                  pw.Center(child: pw.Text('تاريخ: $_todayDate', style: const pw.TextStyle(fontSize: 12))),
                  pw.SizedBox(height: 15),

                  pw.Row(
                    crossAxisAlignment: pw.CrossAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          children: [
                            pw.Container(
                              color: PdfColors.grey300,
                              width: double.infinity,
                              padding: const pw.EdgeInsets.all(4),
                              child: pw.Center(child: pw.Text('المقبوضات', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                            ),
                            pw.Table.fromTextArray(
                              headers: ['البيان', 'المبلغ'],
                              data: incomeList.map((e) => [e['details'], e['amount'].toString()]).toList(),
                              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                              cellAlignment: pw.Alignment.centerRight,
                            ),
                          ],
                        ),
                      ),
                      pw.SizedBox(width: 10),

                      pw.Expanded(
                        child: pw.Column(
                          children: [
                            pw.Container(
                              color: PdfColors.grey300,
                              width: double.infinity,
                              padding: const pw.EdgeInsets.all(4),
                              child: pw.Center(child: pw.Text('المصروفات', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                            ),
                            pw.Table.fromTextArray(
                              headers: ['البيان', 'المبلغ'],
                              data: expenseList.map((e) => [e['details'], e['amount'].toString()]).toList(),
                              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                              cellAlignment: pw.Alignment.centerRight,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 15),

                  pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black)),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAlignment.start,
                      children: [
                        pw.Text('إجمالي المقبوضات لليوم: $totalIncome'),
                        pw.Text('رصيد اليوم السابق: $prevBalance'),
                        pw.Text('الإجمالي الكلي: $grandTotal'),
                        pw.Text('إجمالي المصروفات: $totalExpense'),
                        pw.Divider(),
                        pw.Text('رصيد اليوم فقط: $finalBalance', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                  ),

                  pw.Spacer(),

                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                    children: [
                      pw.Text('الصندوق /'),
                      pw.Text('المحاسب /'),
                      pw.Text('مسؤول الحسابات /'),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    final transactions = _getTodayTransactions();
    double totalIncome = transactions.where((e) => e['type'] == 'مقبوضات').fold(0.0, (sum, i) => sum + i['amount']);
    double totalExpense = transactions.where((e) => e['type'] == 'مصروفات').fold(0.0, (sum, i) => sum + i['amount']);
    double prevBalance = _getAutoPreviousBalance();
    double grandTotal = totalIncome + prevBalance;
    double finalBalance = grandTotal - totalExpense;

    return Scaffold(
      appBar: AppBar(
        title: const Text('حركة الصندوق اليومية'),
        actions: [
          IconButton(onPressed: _exportPDF, icon: const Icon(Icons.picture_as_pdf)),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Column(
                    children: [
                      Text('رصيد اليوم السابق (تلقائي): $prevBalance ريال', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Text('المقبوضات: $totalIncome', style: const TextStyle(color: Colors.green)),
                          Text('المصروفات: $totalExpense', style: const TextStyle(color: Colors.red)),
                          Text('الرصيد النهائي: $finalBalance', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedType,
                      items: ['مقبوضات', 'مصروفات']
                          .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                          .toList(),
                      onChanged: (val) => setState(() => _selectedType = val!),
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'المبلغ', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _detailsController,
                decoration: const InputDecoration(labelText: 'البيان (التوريد / المصرف)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _addTransaction,
                icon: const Icon(Icons.add),
                label: const Text('حفظ الحركة'),
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(40)),
              ),
              const Divider(),

              Expanded(
                child: ListView.builder(
                  itemCount: transactions.length,
                  itemBuilder: (context, index) {
                    final item = transactions[index];
                    bool isIncome = item['type'] == 'مقبوضات';
                    return ListTile(
                      title: Text(item['details']),
                      subtitle: Text(item['time']),
                      trailing: Text(
                        '${item['amount']} ريال',
                        style: TextStyle(color: isIncome ? Colors.green : Colors.red, fontWeight: FontWeight.bold),
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
  }
}
