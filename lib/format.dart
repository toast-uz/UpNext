// Simple lexical analysis and syntax analysis engine
// for the flexible format string
//
// example
/*
main() {
  Format fmt = Format({
    '{' : 'open',
    '}' : 'close',
    'hh': hh,
    'hhhh': hhhh,
  });
  print(fmt.apply('こ{んhhhhに{ちhhは}、あり}がとう'));
}

FormatFunction hh = () {return '関数1';};
FormatFunction hhhh = () {return '関数2';};
*/

// Flex format string
typedef String FormatFunction();

class Format {
  final Map<String, dynamic> _rule;

  Format(this._rule);

  // parameter 'words' has side effects in this method
  String apply(String fmt, [List<String> words]) {
    String output = '';
    bool success = true;
    if (words == null) words = fmtWording(fmt);
    while (words.isNotEmpty) {
      final word = words.removeAt(0);
      final rule = _rule[word];
      if (rule != null) {
        if (rule == 'open') {
          output += apply(fmt, words);
        } else if (rule == 'close') {
          break;
        } else {
          String outputAdd = Function.apply(rule as FormatFunction, []);
          if ((outputAdd == null) || (outputAdd == '')) success = false;
          output += outputAdd;
        }
      } else {
        output += word;
      }
    }
    if (!success) output = '';
    return output;
  }

  List<String> fmtWording(String fmt) {
    List<String> result = [];
    Runes fmtChars = fmt.runes;
    for (int i = 0; i < fmtChars.length; i++) {
      for (int j = fmtChars.length; j > i; j--) {
        String substring = String.fromCharCodes(fmtChars, i, j);
        if ((_rule[substring] != null) || (j - i == 1)) {
          result.add(substring);
          i = j - 1;
          break;
        }
      }
    }
    return result;
  }
}