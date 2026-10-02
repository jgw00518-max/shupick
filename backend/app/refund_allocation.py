"""결제 스냅샷의 할인·포인트를 정수 금액으로 배분한다."""


def allocate(total, weights):
    denominator = sum(weights)
    if not denominator:
        if total:
            raise ValueError('Cannot allocate to zero-priced items')
        return [0] * len(weights)
    values = [total * weight // denominator for weight in weights]
    remainder = total - sum(values)
    order = sorted(range(len(weights)), key=lambda i: (-(total * weights[i] % denominator), i))
    for index in order[:remainder]:
        values[index] += 1
    return values


def line_allocations(rows, coupon, points):
    weights = [int(row['unit_price']) * int(row['quantity']) for row in rows]
    discounts = allocate(coupon, weights)
    # 할인 후 금액에 포인트를 배분하여 음수 결제액을 방지한다.
    net = [weight - discount for weight, discount in zip(weights, discounts)]
    spending = allocate(points, net)
    return {row['order_item_id']: (amount - used, used, int(row['quantity']))
            for row, amount, used in zip(rows, net, spending)}


def quantity_share(total, quantity, start, count):
    """수량 구간별 배분: 마지막까지 반품하면 원래 총액과 정확히 일치한다."""
    return total * (start + count) // quantity - total * start // quantity
