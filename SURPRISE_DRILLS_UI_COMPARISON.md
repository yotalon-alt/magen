# תרגילי הפתעה - השוואת מבנה UI

## עדכון העקרונות ✅

### שינויים ברשימת העקרונות:

| # | **לפני** | **אחרי** | **שינוי** |
|---|-----------|----------|-----------|
| 1 | קשר עין | קשר עין | ✅ ללא שינוי |
| 2 | בחירת ציר התקדמות | בחירת ציר התקדמות | ✅ ללא שינוי |
| 3 | **זיהוי** איום עיקרי ואיום משני | איום עיקרי ואיום משני | 🔧 **הוסר "זיהוי"** |
| 4 | קצב אש ומרחק | קצב אש ומרחק | ✅ ללא שינוי |
| 5 | ירי בטוח **וקרוב** | ירי בטוח **בתוך קהל** | 🔧 **שונה** |
| 6 | וידוא **נטרול** | וידוא **ניטרול** | 🔧 **תוקן כתיב** |
| 7 | זיהוי **והדרכות** | זיהוי **והדחה** | 🔧 **שונה** |
| 8 | רמת ביצוע | רמת ביצוע | ✅ ללא שינוי |

---

## מבנה מסך "תרגילי הפתעה"

### 📋 כותרת ומידע כללי:
```
┌────────────────────────────────────────────────┐
│  תרגילי הפתעה                                 │
│                                                │
│  יישוב/מחלקה:  [dropdown קצרין ▼]             │
│  כמות נוכחים:  [5________]                    │
└────────────────────────────────────────────────┘
```

### ➕ כפתור הוספת עיקרון:
```
┌────────────────────────────────────────────────┐
│                                                │
│   [ הוסף עיקרון + ]                           │
│                                                │
└────────────────────────────────────────────────┘
```

### 📊 רשימת עקרונות (בלוקים):
```
┌─────────────────────────────────────────────────────────────┐
│  🔷 עיקרון 1: קשר עין                         [🗑️ מחק]    │
│                                                             │
│  (ללא שדה כדורים במצב surprise!)                           │
│                                                             │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  🔷 עיקרון 2: בחירת ציר התקדמות                [🗑️ מחק]    │
│                                                             │
│  (ללא שדה כדורים במצב surprise!)                           │
│                                                             │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  🔷 עיקרון 3: איום עיקרי ואיום משני             [🗑️ מחק]    │
│                                                             │
│  (ללא שדה כדורים במצב surprise!)                           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**⚠️ הבדל מרכזי:**
- **טווח קצר/רחוק:** יש שדה "מספר כדורים" ⬅️ `if (widget.mode == 'range')`
- **תרגילי הפתעה:** **אין** שדה כדורים ⬅️ `else if (widget.mode == 'surprise')`

---

## טבלת חניכים (RTL Layout)

### מבנה הטבלה:
```
┌──────────────────────────────────────────────────────────────────────────────┐
│  הזנת ציונים - החלק ימינה לגלילה                                           │
├──────┬──────────┬──────────────┬──────────────┬──────────────┬──────────────┤
│ מספר │   שם     │  קשר עין    │  בחירת ציר   │  איום עיקרי  │  סה"כ        │
│ מס' │  חניך    │   (1-10)    │   (1-10)     │   (1-10)     │ ציון         │
├──────┼──────────┼──────────────┼──────────────┼──────────────┼──────────────┤
│  1   │ חייל א   │    [8]      │    [7]       │    [9]       │  24 / 30     │
├──────┼──────────┼──────────────┼──────────────┼──────────────┼──────────────┤
│  2   │ חייל ב   │    [9]      │    [8]       │    [8]       │  25 / 30     │
├──────┼──────────┼──────────────┼──────────────┼──────────────┼──────────────┤
│  3   │ חייל ג   │    [7]      │    [9]       │    [7]       │  23 / 30     │
└──────┴──────────┴──────────────┴──────────────┴──────────────┴──────────────┘
     ↑            ↑              ↑              ↑              ↑
   ימין         אמצע          שמאל           שמאל           שמאל
 (קבוע)       (קבוע)        (גלילה)        (גלילה)        (גלילה)
```

### ✅ תאימות RTL:
1. **עמודת מספר** - **קבועה מימין** (frozen column, appears first in RTL)
2. **עמודת שם** - **קבועה** (frozen column)
3. **עמודות עקרונות** - **גוללות אופקית** (scrollable)
4. **עמודת סה"כ** - **גוללת** (scrollable)

### 🎯 קוד מפתח:
```dart
// Frozen columns on the left: Number FIRST (appears RIGHT in RTL), then Name
Row(
  children: [
    // Column 1: Number (80px) - APPEARS RIGHT IN RTL ✅
    SizedBox(
      width: 80,
      child: Column([
        Text('מספר'),  // Header
        ...traineeNumberFields,  // Editable sequential numbers
      ]),
    ),
    
    // Column 2: Name (160px)
    SizedBox(
      width: 160,
      child: Column([
        Text('Name'),  // Header
        ...traineeNameFields,
      ]),
    ),
    
    // Scrollable principle columns
    Expanded(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row([
          ...principleColumns,  // Dynamic based on added principles
          summaryColumn,
        ]),
      ),
    ),
  ],
)
```

---

## Dropdown "הוסף עיקרון"

### UI:
```
┌────────────────────────────────────────────────┐
│  בחר עיקרון:                                   │
│  ┌──────────────────────────────────────────┐  │
│  │  קשר עין                            ▼   │  │
│  ├──────────────────────────────────────────┤  │
│  │  קשר עין                                 │  │
│  │  בחירת ציר התקדמות                       │  │
│  │  איום עיקרי ואיום משני                   │  │
│  │  קצב אש ומרחק                            │  │
│  │  ירי בטוח בתוך קהל                       │  │
│  │  וידוא ניטרול                            │  │
│  │  זיהוי והדחה                             │  │
│  │  רמת ביצוע                               │  │
│  └──────────────────────────────────────────┘  │
└────────────────────────────────────────────────┘
```

**🔒 רשימה סגורה - 8 אפשרויות קבועות בלבד!**

### קוד:
```dart
DropdownButtonFormField<String>(
  items: _availableItems.map((item) =>  // Dynamic based on mode
    DropdownMenuItem(value: item, child: Text(item)),
  ).toList(),
  onChanged: (selectedPrinciple) {
    setState(() {
      stations.add(Station(name: selectedPrinciple));
    });
  },
)

// Mode-based getter:
List<String> get _availableItems =>
    widget.mode == 'surprise' 
      ? availablePrinciples    // 8 principles ✅
      : availableStations;     // 14 stations
```

---

## Validation Rules

### ציון עיקרון (1-10):
```dart
onChanged: (v) {
  final score = int.tryParse(v) ?? 0;
  
  if (widget.mode == 'surprise') {
    // Surprise mode: 1-10 scale
    if (score < 0 || score > 10) {
      showSnackBar('ציון חייב להיות בין 1 ל-10');
      return;
    }
  } else {
    // Range mode: hits limited by bullets
    if (score > station.bulletsCount) {
      showSnackBar('פגיעות לא יכולות לעלות על ${station.bulletsCount}');
      return;
    }
  }
  
  trainee.hits[stationIndex] = score;
}
```

### לפני שמירה:
```dart
// Check at least one principle added
if (stations.isEmpty) {
  showSnackBar('אנא הוסף עיקרון אחד לפחות');
  return;
}

// Check all principles have names
for (var station in stations) {
  if (station.name.isEmpty) {
    showSnackBar('אנא הזן שם לעיקרון');
    return;
  }
}

// Surprise mode: NO bullets validation ✅
// (skipped via `if (widget.mode == 'range')`)
```

---

## Export Structure (Excel)

### קובץ: `משוב תרגילי הפתעה - 2026-01-02.xlsx`

### גיליון: `משוב תרגילי הפתעה` (RTL)

### Headers:
| סוג משוב | שם המדריך | פיקוד | חטיבה | תאריך | קשר עין | בחירת ציר | איום עיקרי | קצב אש | ירי בטוח | וידוא | זיהוי | רמת ביצוע | סך הכול | ממוצע |
|----------|-----------|-------|-------|-------|---------|----------|-----------|--------|----------|-------|------|-----------|---------|-------|

### Sample Row:
| משוב תרגילי הפתעה | רס״פ כהן | חטיבת גולני | 474 | 02/01/2026 12:30 | 8 | 7 | 9 | 6 | 8 | 7 | 9 | 8 | 62 | 7.75 |

### קוד:
```dart
final List<String> principleNames = [
  'קשר עין',
  'בחירת ציר התקדמות',
  'איום עיקרי ואיום משני',      // ✅ Updated
  'קצב אש ומרחק',
  'ירי בטוח בתוך קהל',           // ✅ Updated
  'וידוא ניטרול',                // ✅ Updated spelling
  'זיהוי והדחה',                 // ✅ Updated
  'רמת ביצוע',
];

sheet.isRTL = true;  // Hebrew RTL mode ✅
```

---

## Data Flow Summary

```
┌─────────────────────────────────────────────────────────────────┐
│  תרגילי הפתעה Screen                                           │
│  (mode: 'surprise')                                            │
└─────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│  RangeTrainingPage                                             │
│  • mode='surprise' → uses availablePrinciples (8 items)        │
│  • No bullets field                                            │
│  • Score validation: 1-10                                      │
│  • Dynamic labels via getters                                  │
└─────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│  Firestore: feedbacks collection                               │
│  {                                                             │
│    "exercise": "תרגילי הפתעה",                                │
│    "folder": "משוב תרגילי הפתעה",                             │
│    "rangeType": "הפתעה",                                      │
│    "mode": "surprise",                                        │
│    "stations": [                                              │
│      {"name": "קשר עין", "bulletsCount": 0, ...},            │
│      {"name": "איום עיקרי ואיום משני", ...}                  │
│    ],                                                         │
│    "trainees": [                                              │
│      {"name": "חייל א", "hits": {"station_0": 8, ...}}       │
│    ]                                                          │
│  }                                                            │
└─────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│  FeedbackExportService.exportSurpriseDrillsToXlsx()            │
│  • Generates XLSX with 8 principle columns                    │
│  • RTL mode enabled                                           │
│  • Hebrew filename                                            │
│  • Calculations: totalScore, averageScore                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## Side-by-Side Comparison

### טווח קצר (Range Mode):
```dart
mode: 'range'
rangeType: 'קצרים'

Items: 14 מקצים (stations)
  - הרמות, שלשות, UP עד UP, ...
  - מקצה ידני (free text)

Bullets field: ✅ VISIBLE
  TextField(labelText: 'מספר כדורים')

Score validation:
  if (score > station.bulletsCount) { error }

Folder: 'מטווחי ירי'
SubFolder: 'דיווח קצר'
```

### תרגילי הפתעה (Surprise Mode):
```dart
mode: 'surprise'
rangeType: 'הפתעה'

Items: 8 עקרונות (principles)
  - קשר עין
  - בחירת ציר התקדמות
  - איום עיקרי ואיום משני       ✅ Updated
  - קצב אש ומרחק
  - ירי בטוח בתוך קהל            ✅ Updated
  - וידוא ניטרול                 ✅ Updated
  - זיהוי והדחה                  ✅ Updated
  - רמת ביצוע

Bullets field: ❌ HIDDEN
  (conditional: if widget.mode == 'range')

Score validation:
  if (score < 0 || score > 10) { error }

Folder: 'משוב תרגילי הפתעה'
SubFolder: 'תרגילי הפתעה'
```

---

**✅ המערכת מוכנה לשימוש!**
