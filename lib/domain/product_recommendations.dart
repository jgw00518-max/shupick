import 'models.dart';

/// 신규 상품이나 연결 실패 시에도 상품 번호에 의존하지 않는 추천을 제공합니다.
List<Product> similarProducts(
  Product source,
  List<Product> products, {
  int limit = 4,
}) {
  final candidates = <int, Product>{
    for (final product in products)
      if (product.id != source.id && _compatible(source.gender, product.gender))
        product.id: product,
  }.values.toList();
  candidates.sort((a, b) {
    for (final comparison in [
      _match(
        source.subcategory,
        b.subcategory,
      ).compareTo(_match(source.subcategory, a.subcategory)),
      _match(
        source.middleCategory,
        b.middleCategory,
      ).compareTo(_match(source.middleCategory, a.middleCategory)),
      _match(
        source.gender,
        b.gender,
      ).compareTo(_match(source.gender, a.gender)),
      (a.price - source.price).abs().compareTo((b.price - source.price).abs()),
      a.id.compareTo(b.id),
    ]) {
      if (comparison != 0) return comparison;
    }
    return 0;
  });
  return candidates.take(limit).toList();
}

int _match(String source, String candidate) => source == candidate ? 1 : 0;

bool _compatible(String source, String candidate) => switch (source) {
  '키즈' => candidate == '키즈',
  '남성' => candidate == '남성' || candidate == '공용',
  '여성' => candidate == '여성' || candidate == '공용',
  _ => candidate != '키즈',
};
