from app.refund_allocation import allocate, line_allocations, quantity_share


def test_policy_example():
    rows = [dict(order_item_id=1,unit_price=60000,quantity=1),dict(order_item_id=2,unit_price=40000,quantity=1)]
    assert line_allocations(rows,10000,5000)=={1:(51000,3000,1),2:(34000,2000,1)}


def test_rounding_and_partial_quantity_conserve_totals():
    assert allocate(1000,[1,1,1])==[334,333,333]
    assert sum(quantity_share(1000,3,start,1) for start in range(3))==1000
    rows=[dict(order_item_id=1,unit_price=1,quantity=1),dict(order_item_id=2,unit_price=2,quantity=1)]
    result=line_allocations(rows,1,2)
    assert sum(row[0] for row in result.values())==0
    assert sum(row[1] for row in result.values())==2
