module spells {

    pure def flatten(__in: Set[Set[__a]]): Set[__a] = {
        __in.fold(Set.empty[__a])((acc, s) => acc.union(s))
    }
}