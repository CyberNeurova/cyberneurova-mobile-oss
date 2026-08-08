import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/features/chat/presentation/widgets/web_preview.dart';

void main() {
  group('assembleWebPreview', () {
    test('offers nothing when no block is web code', () {
      expect(
        assembleWebPreview([
          (language: 'python', code: 'print("hi")'),
          (language: 'bash', code: 'ls -la'),
        ]),
        isNull,
      );
    });

    test('runs a single self-contained page', () {
      final doc = assembleWebPreview([
        (language: 'html', code: '<!doctype html><html><body>hi</body></html>'),
      ]);

      expect(doc, isNotNull);
      expect(doc!.anchorIndex, 0);
      expect(doc.partCount, 1);
      expect(doc.html, contains('hi'));
    });

    test('folds a separate CSS and JS block into the page', () {
      // The shape models actually emit: three blocks, and the HTML referring
      // to files that will never exist on a phone.
      final doc = assembleWebPreview([
        (language: 'html', code: '''
<!doctype html>
<html>
<head><link rel="stylesheet" href="style.css"></head>
<body><canvas id="c"></canvas><script src="game.js"></script></body>
</html>'''),
        (language: 'css', code: 'canvas { background: #111; }'),
        (language: 'javascript', code: 'const c = document.getElementById("c");'),
      ]);

      expect(doc, isNotNull);
      expect(doc!.partCount, 3);
      // Stitched in…
      expect(doc.html, contains('canvas { background: #111; }'));
      expect(doc.html, contains('const c = document.getElementById'));
      // …and the dead references removed, or the page renders unstyled and
      // the user reads that as the preview being broken.
      expect(doc.html, isNot(contains('style.css')));
      expect(doc.html, isNot(contains('game.js')));
    });

    test('keeps CDN references, which are real resources', () {
      final doc = assembleWebPreview([
        (
          language: 'html',
          code: '<html><head>'
              '<script src="https://cdn.example/three.js"></script>'
              '</head><body></body></html>'
        ),
      ]);

      expect(doc!.html, contains('https://cdn.example/three.js'));
    });

    test('wraps a bare fragment so it renders at all', () {
      final doc = assembleWebPreview([
        (language: 'html', code: '<div class="board">x</div>'),
        (language: 'css', code: '.board { color: red; }'),
      ]);

      expect(doc, isNotNull);
      expect(doc!.html, contains('<!doctype html>'));
      expect(doc.html, contains('viewport'));
      expect(doc.html, contains('.board { color: red; }'));
      expect(doc.html, contains('<div class="board">x</div>'));
    });

    test('recognises unlabelled HTML, since models label about half the time', () {
      final doc = assembleWebPreview([
        (language: null, code: '<!DOCTYPE html><html><body>y</body></html>'),
      ]);
      expect(doc, isNotNull);
    });

    test('does not mistake a shell one-liner for markup', () {
      // `<` opens plenty of things that are not HTML.
      expect(
        assembleWebPreview([
          (language: 'bash', code: 'diff <(sort a) <(sort b)'),
        ]),
        isNull,
      );
    });

    test('anchors the action on the HTML block, not the first block', () {
      final doc = assembleWebPreview([
        (language: 'css', code: 'body { margin: 0; }'),
        (language: 'html', code: '<html><body>z</body></html>'),
      ]);

      // The Run action belongs where the user is looking when they wonder
      // whether they can see the thing.
      expect(doc!.anchorIndex, 1);
    });

    test('injects styles inside head when there is one', () {
      final doc = assembleWebPreview([
        (language: 'html', code: '<html><head><title>t</title></head><body></body></html>'),
        (language: 'css', code: 'p{}'),
      ]);

      final html = doc!.html;
      expect(html.indexOf('p{}'), lessThan(html.indexOf('</head>')));
    });

    test('injects script at the end of body so the DOM exists first', () {
      // A game script that runs before its canvas exists throws on load, and
      // the user sees a blank page with no clue why.
      final doc = assembleWebPreview([
        (language: 'html', code: '<html><body><canvas></canvas></body></html>'),
        (language: 'js', code: 'start()'),
      ]);

      final html = doc!.html;
      expect(html.indexOf('<canvas>'), lessThan(html.indexOf('start()')));
      expect(html.indexOf('start()'), lessThan(html.indexOf('</body>')));
    });
  });
}
