#!/bin/bash

# --- CONFIGURATION ---
DB_NAME="uc_tracker_final"
DB_USER="uc_admin"
DB_PASS=$(openssl rand -base64 12)
APP_DIR="/var/www/html"

echo "====================================================="
echo "   UC TRACKER ULTIMATE - DETAILED EMPLOYER REPORTS"
echo "====================================================="

# 1. System Environment Setup
apt update && apt install -y apache2 mariadb-server php php-mysql libapache2-mod-php php-pdo php-mbstring php-bcmath

# 2. Database Schema
mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
USE $DB_NAME;

CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL
);

CREATE TABLE IF NOT EXISTS daily_records (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    log_date DATE NOT NULL,
    start_mileage DECIMAL(10,2) DEFAULT 0,
    end_mileage DECIMAL(10,2) DEFAULT 0,
    UNIQUE KEY user_date (user_id, log_date)
);

CREATE TABLE IF NOT EXISTS income_entries (
    id INT AUTO_INCREMENT PRIMARY KEY,
    record_id INT NOT NULL,
    employer_name VARCHAR(100),
    income_amount DECIMAL(10,2) DEFAULT 0,
    pension_percent DECIMAL(5,2) DEFAULT 0,
    fees_percent DECIMAL(5,2) DEFAULT 0,
    FOREIGN KEY (record_id) REFERENCES daily_records(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS expenses (
    id INT AUTO_INCREMENT PRIMARY KEY,
    record_id INT NOT NULL,
    description VARCHAR(255),
    amount DECIMAL(10,2) DEFAULT 0,
    FOREIGN KEY (record_id) REFERENCES daily_records(id) ON DELETE CASCADE
);

INSERT IGNORE INTO users (username, password) VALUES ('admin', '$(php -r "echo password_hash('admin123', PASSWORD_DEFAULT);")');
EOF

# 3. Create db.php
cat <<EOF > $APP_DIR/db.php
<?php
if (session_status() === PHP_SESSION_NONE) { session_start(); }
\$host = 'localhost';
\$db   = '$DB_NAME';
\$user = '$DB_USER';
\$pass = '$DB_PASS';
try {
    \$pdo = new PDO("mysql:host=\$host;dbname=\$db;charset=utf8mb4", \$user, \$pass, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC
    ]);
} catch (Exception \$e) { die("DB Error."); }
?>
EOF

# 4. Create index.php (Dashboard)
cat <<'EOF' > $APP_DIR/index.php
<?php
require_once 'db.php';
if (!isset($_SESSION['user_id'])) { header("Location: login.php"); exit; }
$user_id = $_SESSION['user_id'];
$today = date('Y-m-d');
$stmt = $pdo->prepare("SELECT * FROM daily_records WHERE user_id = ? AND log_date = ?");
$stmt->execute([$user_id, $today]);
$log = $stmt->fetch();

$daily_gross = 0; $daily_deds = 0; $daily_exps = 0;
if ($log) {
    $stmt = $pdo->prepare("SELECT * FROM income_entries WHERE record_id = ?");
    $stmt->execute([$log['id']]);
    foreach($stmt->fetchAll() as $j) {
        $daily_gross += $j['income_amount'];
        $daily_deds += ($j['income_amount'] * ($j['pension_percent']/100)) + ($j['income_amount'] * ($j['fees_percent']/100));
    }
    $stmt = $pdo->prepare("SELECT SUM(amount) FROM expenses WHERE record_id = ?");
    $stmt->execute([$log['id']]);
    $daily_exps = $stmt->fetchColumn() ?: 0;
}
?>
<!DOCTYPE html><html><head><title>Dashboard</title><script src="https://cdn.tailwindcss.com"></script></head>
<body class="bg-slate-50 min-h-screen">
<nav class="bg-indigo-900 text-white p-4 flex justify-between items-center shadow-lg">
    <b class="text-xl">UC Tracker</b>
    <div class="space-x-6 text-sm font-bold">
        <a href="index.php">Dashboard</a>
        <a href="report.php">Monthly Report</a>
        <a href="logout.php" class="text-red-300">Logout</a>
    </div>
</nav>
<main class="max-w-xl mx-auto py-12 px-4">
<?php if(!$log): ?>
    <div class="bg-white p-10 rounded-3xl shadow-xl text-center border">
        <h2 class="text-3xl font-black mb-6">Welcome</h2>
        <form action="start_day.php" method="POST">
            <label class="block text-gray-400 text-sm mb-2 font-bold uppercase">Enter Odometer to Start</label>
            <input type="number" step="0.1" name="start_mileage" required class="w-full border-2 p-4 rounded-2xl mb-6 text-2xl text-center outline-none focus:border-indigo-500">
            <button class="w-full bg-indigo-600 text-white font-bold py-4 rounded-2xl text-xl shadow-lg">Start Shift</button>
        </form>
    </div>
<?php elseif($log['end_mileage'] == 0): ?>
    <div class="bg-white p-10 rounded-3xl shadow-xl border">
        <h2 class="text-2xl font-bold mb-8 text-indigo-600">Shift Active</h2>
        <p class="mb-6 text-gray-500">Started at: <b><?= $log['start_mileage'] ?></b> mi</p>
        <a href="end_day.php" class="block w-full bg-green-600 text-white font-bold py-4 rounded-2xl text-center shadow-lg mb-4 hover:bg-green-700 transition">Log End & Income</a>
        <a href="add_expense.php" class="block w-full bg-slate-100 text-slate-700 font-bold py-4 rounded-2xl text-center hover:bg-slate-200 transition">Add Expense</a>
    </div>
<?php else: ?>
    <div class="bg-white p-10 rounded-3xl shadow-xl border">
        <h2 class="text-2xl font-bold text-green-600 mb-4">Day Completed</h2>
        <div class="grid grid-cols-2 gap-4 mb-6">
            <div class="p-3 bg-gray-50 rounded-xl border text-center"><small class="text-gray-400 block">MILES</small><b><?= $log['end_mileage'] - $log['start_mileage'] ?></b></div>
            <div class="p-3 bg-gray-50 rounded-xl border text-center"><small class="text-gray-400 block">NET PROFIT</small><b>£<?= number_format($daily_gross - $daily_deds - $daily_exps, 2) ?></b></div>
        </div>
        <a href="report.php" class="block text-center text-indigo-600 font-bold underline">View Monthly Report</a>
    </div>
<?php endif; ?>
</main></body></html>
EOF

# 5. Create Compact report.php (WITH DETAILED BREAKDOWN)
cat <<'EOF' > $APP_DIR/report.php
<?php
require_once 'db.php';
if (!isset($_SESSION['user_id'])) { header("Location: login.php"); exit; }
$user_id = $_SESSION['user_id'];
$from = $_GET['f'] ?? date('Y-m-d', strtotime('-30 days'));
$to = $_GET['t'] ?? date('Y-m-d');
$rate = 0.45;

// Daily Records
$stmt = $pdo->prepare("SELECT dr.*, 
    (SELECT SUM(income_amount) FROM income_entries WHERE record_id = dr.id) as gross,
    (SELECT SUM(income_amount * (pension_percent/100) + income_amount * (fees_percent/100)) FROM income_entries WHERE record_id = dr.id) as deds,
    (SELECT SUM(amount) FROM expenses WHERE record_id = dr.id) as exps
    FROM daily_records dr WHERE dr.user_id = ? AND dr.log_date BETWEEN ? AND ? ORDER BY dr.log_date ASC");
$stmt->execute([$user_id, $from, $to]);
$logs = $stmt->fetchAll();

// Employer Detailed Summary
$stmt = $pdo->prepare("SELECT employer_name, 
    SUM(income_amount) as total_gross, 
    SUM(income_amount * (pension_percent/100)) as total_pension,
    SUM(income_amount * (fees_percent/100)) as total_fees
    FROM income_entries 
    WHERE record_id IN (SELECT id FROM daily_records WHERE user_id = ? AND log_date BETWEEN ? AND ?)
    GROUP BY employer_name");
$stmt->execute([$user_id, $from, $to]);
$emp_sum = $stmt->fetchAll();

$t = ['g'=>0, 'p'=>0, 'f'=>0, 'e'=>0, 'm'=>0];
foreach($logs as $l) {
    $t['g'] += $l['gross']; 
    $t['e'] += $l['exps'];
    $t['m'] += ($l['end_mileage'] - $l['start_mileage']);
}
foreach($emp_sum as $e) { $t['p'] += $e['total_pension']; $t['f'] += $e['total_fees']; }

$mile_allow = $t['m'] * $rate;
$final_prof = $t['g'] - ($t['p'] + $t['f']) - $t['e'] - $mile_allow;
?>
<!DOCTYPE html><html><head><title>UC Report</title><script src="https://cdn.tailwindcss.com"></script>
<style>
    @media print {
        .no-print { display: none !important; }
        @page { margin: 0.5cm; size: A4; }
        body { background: white !important; font-size: 9pt; }
        .compact-table th, .compact-table td { padding: 3px 5px !important; border: 1px solid #ddd; font-size: 8.5pt !important; }
        .box { border: 1px solid #ccc !important; }
    }
</style>
</head>
<body class="bg-slate-50 p-4">
<div class="max-w-4xl mx-auto bg-white p-6 rounded-lg shadow-md border print:shadow-none print:border-none">
    
    <div class="flex justify-between items-center mb-4 no-print">
        <a href="index.php" class="text-indigo-600 text-sm font-bold">← Dashboard</a>
        <button onclick="window.print()" class="bg-indigo-900 text-white px-4 py-1 rounded text-sm font-bold">Print (1 Page)</button>
    </div>

    <div class="flex justify-between items-end mb-6 border-b pb-4">
        <div>
            <h1 class="text-xl font-black uppercase">UC Earnings & Mileage Report</h1>
            <p class="text-xs text-gray-500">Period: <?= $from ?> to <?= $to ?></p>
        </div>
        <div class="text-right">
            <div class="text-[10px] font-bold text-gray-400 uppercase">Final Profit for UC</div>
            <div class="text-2xl font-black text-indigo-700">£<?= number_format($final_prof, 2) ?></div>
        </div>
    </div>

    <div class="grid grid-cols-4 gap-2 mb-6 text-center">
        <div class="p-2 border rounded bg-slate-50 box"><div class="text-[9px] text-gray-400">GROSS INCOME</div><div class="text-xs font-bold">£<?= number_format($t['g'], 2) ?></div></div>
        <div class="p-2 border rounded bg-slate-50 box"><div class="text-[9px] text-gray-400">MILEAGE ALLOWANCE</div><div class="text-xs font-bold">£<?= number_format($mile_allow, 2) ?></div></div>
        <div class="p-2 border rounded bg-slate-50 box"><div class="text-[9px] text-gray-400">TOTAL DISCOUNTS</div><div class="text-xs font-bold text-red-600">£<?= number_format($t['p'] + $t['f'], 2) ?></div></div>
        <div class="p-2 border rounded bg-slate-50 box"><div class="text-[9px] text-gray-400">TOTAL EXPENSES</div><div class="text-xs font-bold text-red-600">£<?= number_format($t['e'], 2) ?></div></div>
    </div>

    <div class="mb-6">
        <h2 class="text-[10px] font-black uppercase text-indigo-400 mb-2">Detailed Employer Breakdown (Discounts Included)</h2>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2">
            <?php foreach($emp_sum as $e): ?>
            <div class="p-2 border rounded text-[10px] bg-white box">
                <b class="block truncate border-b mb-1 uppercase text-indigo-700"><?= htmlspecialchars($e['employer_name']) ?></b>
                <div class="flex justify-between"><span>Gross:</span><b>£<?= number_format($e['total_gross'], 2) ?></b></div>
                <div class="flex justify-between text-red-500"><span>Pension Deduction:</span><b>-£<?= number_format($e['total_pension'], 2) ?></b></div>
                <div class="flex justify-between text-red-500"><span>Fees Deduction:</span><b>-£<?= number_format($e['total_fees'], 2) ?></b></div>
                <div class="flex justify-between mt-1 pt-1 border-t border-dashed font-bold"><span>Subtotal:</span><span>£<?= number_format($e['total_gross'] - $e['total_pension'] - $e['total_fees'], 2) ?></span></div>
            </div>
            <?php endforeach; ?>
        </div>
    </div>

    <table class="w-full border compact-table text-left">
        <thead class="bg-gray-100 uppercase text-[9px] border-b">
            <tr><th>Date</th><th>Miles</th><th>Gross £</th><th>Pension £</th><th>Fees £</th><th>Exps £</th><th class="text-right">Net Day</th></tr>
        </thead>
        <tbody class="divide-y">
            <?php foreach($logs as $l): 
                $day_net = $l['gross'] - $l['deds'] - $l['exps']; 
                // Fetch daily breakdown for table columns
                $stmt = $pdo->prepare("SELECT SUM(income_amount * (pension_percent/100)) as p, SUM(income_amount * (fees_percent/100)) as f FROM income_entries WHERE record_id = ?");
                $stmt->execute([$l['id']]);
                $deds = $stmt->fetch();
            ?>
            <tr>
                <td class="font-bold"><?= date('d/m/y', strtotime($l['log_date'])) ?></td>
                <td><?= ($l['end_mileage'] - $l['start_mileage']) ?></td>
                <td><?= number_format($l['gross'], 2) ?></td>
                <td class="text-red-500">-<?= number_format($deds['p'], 2) ?></td>
                <td class="text-red-500">-<?= number_format($deds['f'], 2) ?></td>
                <td class="text-red-500">-<?= number_format($l['exps'], 2) ?></td>
                <td class="text-right font-black">£<?= number_format($day_net, 2) ?></td>
            </tr>
            <?php endforeach; ?>
        </tbody>
        <tfoot class="bg-gray-50 font-black border-t uppercase text-[9px]">
            <tr>
                <td>TOTALS</td><td><?= $t['m'] ?></td><td>£<?= number_format($t['g'], 2) ?></td><td>-£<?= number_format($t['p'], 2) ?></td><td>-£<?= number_format($t['f'], 2) ?></td><td>-£<?= number_format($t['e'], 2) ?></td><td class="text-right">£<?= number_format($t['g']-$t['p']-$t['f']-$t['e'], 2) ?></td>
            </tr>
        </tfoot>
    </table>
    
    <div class="mt-4 no-print flex gap-2">
        <form class="flex gap-2">
            <input type="date" name="f" value="<?= $from ?>" class="border p-1 rounded text-xs">
            <input type="date" name="t" value="<?= $to ?>" class="border p-1 rounded text-xs">
            <button class="bg-indigo-600 text-white px-3 rounded text-xs">Filter</button>
        </form>
    </div>
</div>
</body></html>
EOF

# 6. Action Scripts
cat <<'EOF' > $APP_DIR/start_day.php
<?php include 'db.php'; if($_SERVER['REQUEST_METHOD']=='POST'){
$stmt=$pdo->prepare("INSERT INTO daily_records (user_id,log_date,start_mileage) VALUES (?,?,?) ON DUPLICATE KEY UPDATE start_mileage=VALUES(start_mileage)");
$stmt->execute([$_SESSION['user_id'],date('Y-m-d'),$_POST['start_mileage']]); } header("Location: index.php"); ?>
EOF

cat <<'EOF' > $APP_DIR/end_day.php
<?php include 'db.php'; 
if($_SERVER['REQUEST_METHOD']=='POST'){
$stmt=$pdo->prepare("SELECT id FROM daily_records WHERE user_id=? AND log_date=?"); $stmt->execute([$_SESSION['user_id'],date('Y-m-d')]); $rid=$stmt->fetchColumn();
$pdo->prepare("DELETE FROM income_entries WHERE record_id=?")->execute([$rid]);
foreach($_POST['emp'] as $k=>$v){ if(!empty($v)){
$pdo->prepare("INSERT INTO income_entries (record_id,employer_name,income_amount,pension_percent,fees_percent) VALUES (?,?,?,?,?)")
->execute([$rid, $v, $_POST['amt'][$k], $_POST['pen'][$k], $_POST['fee'][$k]]); }}
$pdo->prepare("UPDATE daily_records SET end_mileage=? WHERE id=?")->execute([$_POST['end_m'],$rid]);
header("Location: index.php"); exit; }
?>
<!DOCTYPE html><html><head><script src="https://cdn.tailwindcss.com"></script></head>
<body class="bg-slate-50 p-6 flex justify-center"><form method="POST" class="max-w-xl w-full bg-white p-8 rounded-3xl shadow-xl border">
<h2 class="text-xl font-bold mb-4 text-indigo-800">Complete Shift Details</h2>
<label class="block text-[10px] font-bold text-gray-400 uppercase">End Odometer</label>
<input type="number" step="0.1" name="end_m" required class="w-full border-2 p-3 rounded-xl mb-6">
<div id="j" class="space-y-3">
<div class="p-4 bg-slate-50 rounded-2xl border">
<input name="emp[]" placeholder="Employer" class="w-full border p-2 rounded mb-2 text-sm">
<div class="grid grid-cols-3 gap-2">
<input name="amt[]" step="0.01" type="number" placeholder="Gross £" class="border p-2 rounded text-xs">
<input name="pen[]" type="number" step="0.1" placeholder="Pension %" class="border p-2 rounded text-xs">
<input name="fee[]" type="number" step="0.1" placeholder="Fees %" class="border p-2 rounded text-xs">
</div></div></div>
<button type="button" onclick="document.getElementById('j').innerHTML += '<div class=\'p-4 bg-slate-50 rounded-2xl border mt-3\'><input name=\'emp[]\' placeholder=\'Employer\' class=\'w-full border p-2 rounded mb-2 text-sm\'><div class=\'grid grid-cols-3 gap-2\'><input name=\'amt[]\' step=\'0.01\' type=\'number\' placeholder=\'Gross £\' class=\'border p-2 rounded text-xs\'><input name=\'pen[]\' type=\'number\' step=\'0.1\' placeholder=\'Pension %\' class=\'border p-2 rounded text-xs\'><input name=\'fee[]\' type=\'number\' step=\'0.1\' placeholder=\'Fees %\' class=\'border p-2 rounded text-xs\'></div></div>'" class="text-indigo-600 text-xs font-bold mt-2">+ Add Another Employer</button>
<button type="submit" class="w-full bg-indigo-600 text-white p-4 rounded-xl font-bold mt-8 shadow-lg">Finalize Records</button></form></body></html>
EOF

cat <<'EOF' > $APP_DIR/add_expense.php
<?php require_once 'db.php'; if($_SERVER['REQUEST_METHOD']=='POST'){
$stmt=$pdo->prepare("SELECT id FROM daily_records WHERE user_id=? AND log_date=?"); $stmt->execute([$_SESSION['user_id'],date('Y-m-d')]); $rid=$stmt->fetchColumn();
if($rid){ $pdo->prepare("INSERT INTO expenses (record_id,description,amount) VALUES (?,?,?)")->execute([$rid,$_POST['d'],$_POST['a']]); }
header("Location: index.php"); exit; } ?>
<!DOCTYPE html><html><head><script src="https://cdn.tailwindcss.com"></script></head><body class="bg-slate-50 flex items-center justify-center min-h-screen">
<form method="POST" class="bg-white p-8 rounded-3xl shadow-xl border w-full max-w-sm">
<h2 class="font-bold mb-6 text-indigo-900">Log Business Expense</h2>
<input name="d" placeholder="Description (e.g. Parking)" required class="w-full border p-3 mb-3 rounded-xl"><input name="a" type="number" step="0.01" required placeholder="Amount £" class="w-full border p-3 mb-6 rounded-xl">
<button class="w-full bg-indigo-900 text-white p-3 rounded-xl font-bold">Save Expense</button></form></body></html>
EOF

cat <<'EOF' > $APP_DIR/login.php
<?php require_once 'db.php'; if($_SERVER['REQUEST_METHOD']=='POST'){
$stmt=$pdo->prepare("SELECT * FROM users WHERE username=?"); $stmt->execute([$_POST['u']]); $u=$stmt->fetch();
if($u && password_verify($_POST['p'],$u['password'])){ $_SESSION['user_id']=$u['id']; header("Location: index.php"); exit; } } ?>
<!DOCTYPE html><html><head><script src="https://cdn.tailwindcss.com"></script></head><body class="bg-slate-900 h-screen flex items-center justify-center font-sans">
<form method="POST" class="bg-white p-10 rounded-3xl w-full max-w-sm text-center shadow-2xl border-4 border-indigo-500">
<h2 class="font-black text-3xl mb-8 text-indigo-900">UC TRACKER</h2>
<input name="u" placeholder="Username" class="w-full border-2 p-4 rounded-2xl mb-4 outline-none focus:border-indigo-600">
<input type="password" name="p" placeholder="Password" class="w-full border-2 p-4 rounded-2xl mb-8 outline-none focus:border-indigo-600">
<button class="w-full bg-indigo-600 text-white py-4 rounded-2xl font-bold text-xl shadow-lg">Login</button></form></body></html>
EOF

cat <<'EOF' > $APP_DIR/logout.php
<?php session_start(); session_destroy(); header("Location: login.php"); ?>
EOF

# 7. Final Permissions
chown -R www-data:www-data $APP_DIR
chmod -R 755 $APP_DIR

echo "-----------------------------------------------------"
echo "INSTALLATION SUCCESSFUL!"
echo "URL: http://$(hostname -I | awk '{print $1}')/"
echo "Default Login: admin / admin123"
echo "-----------------------------------------------------"
