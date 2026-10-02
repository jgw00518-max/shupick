from app.catalog import category_tree

def test_taxonomy_supports_leaf_and_child_categories():
    rows=[dict(category_id=1,parent_category_id=None,category_name='신발'),
          dict(category_id=2,parent_category_id=1,category_name='운동화'),
          dict(category_id=3,parent_category_id=2,category_name='러닝화'),
          dict(category_id=4,parent_category_id=1,category_name='부츠')]
    assert category_tree(rows)=={'운동화':['러닝화'],'부츠':[]}

def test_empty_taxonomy():
    assert category_tree([])=={}
