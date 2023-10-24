module spell {
    pure def crossproduct(__s1: Set[a], __s2: Set[b]): Set[(a, b)] =
        __s1.fold(
            Set(),
            (acc1, a) => acc1.union(__s2.fold(
                Set(),
                (acc2, b) => acc2.union(Set((a, b)))
            ))
        )

    run crossproductTest = {
        all { 
            crossproduct(Set(1, 2), Set("a", "b")) == Set((1, "a"), (1, "b"), (2, "a"), (2, "b")),
            crossproduct(Set(1, 2), Set()) == Set(),
            crossproduct(Set(), Set()) == Set(),
        }
    }
}