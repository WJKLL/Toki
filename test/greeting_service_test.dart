// test/greeting_service_test.dart
// S-22 问候语服务单元测试(v1.26.0):
//  - 时钟注入锚定:节日(精确日) > 节气(窗口) > 时段 优先级;
//  - 确定性:同一时钟两次调用结果一致(同小时稳定,防 UI 闪变);
//  - 用户名尾缀拼接。
import 'package:flutter_test/flutter_test.dart';
import 'package:xiangjugong/core/greeting/s22_greeting_service.dart';

void main() {
  GreetingService at(DateTime now) => GreetingService(clock: () => now);

  test('春节日(2026-02-17)命中节日文案', () {
    final String text = at(DateTime(2026, 2, 17, 9)).greetingFor();
    // v1.38.1:未传用户名 → 无 'XX' 占位尾缀。
    expect(text, isNot(endsWith('，XX')));
    expect(text, isNot(contains('XX')));
    expect(
      text,
      anyOf(contains('春节'), contains('新年'), contains('恭喜'), contains('马年')),
    );
  });

  test('节气日(2026-03-20 春分)命中节气文案', () {
    expect(at(DateTime(2026, 3, 20, 12)).greetingFor(), '今日春分');
  });

  test('节气容差窗口(2026-03-21)仍命中(日期表精度容差)', () {
    expect(at(DateTime(2026, 3, 21, 12)).greetingFor(), '今日春分');
  });

  test('普通日按时段(2026-04-10 上午)', () {
    final String text = at(DateTime(2026, 4, 10, 10)).greetingFor();
    expect(text, isNot(endsWith('，XX')));
    expect(
      text,
      anyOf(contains('上午'), contains('元气'), contains('晨'), contains('精神')),
    );
  });

  test('深夜跨零点时段(2026-04-11 02:00)', () {
    final String text = at(DateTime(2026, 4, 11, 2)).greetingFor();
    expect(
      text,
      anyOf(contains('夜深'), contains('熬夜'), contains('晚安'), contains('安眠')),
    );
  });

  test('确定性:同一小时多次调用结果一致(防重建闪变)', () {
    final GreetingService service = at(DateTime(2026, 4, 10, 10, 30));
    expect(service.greetingFor(), service.greetingFor());
  });

  test('跨小时结果可变化(seed 含小时)', () {
    final String h10 = at(DateTime(2026, 4, 10, 10)).greetingFor();
    final String h11 = at(DateTime(2026, 4, 10, 11)).greetingFor();
    // 两个不同小时各自稳定即可;不一定互异(池内可能重合),不断言不等。
    expect(at(DateTime(2026, 4, 10, 11)).greetingFor(), h11);
    expect(h10, isNotEmpty);
  });

  test('自定义用户名尾缀', () {
    final String text = at(DateTime(2026, 4, 10, 10))
        .greetingFor(userName: '小箱');
    expect(text, endsWith('，小箱'));
  });
}
