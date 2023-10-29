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

    //--------------------------------------------------------------------------
    /// An annotation for writing preconditions.
    pure def require(__cond: bool): bool = __cond

    /// Remove a set element.
    pure def setRemove(__set: Set[a], __elem: a): Set[a] = {
        __set.exclude(Set(__elem))
    }

    /// Remove a map entry.
    pure def mapRemove(__map: a -> b, __key: a): a -> b = {
        __map.keys().setRemove(__key).mapBy(__k => __map.get(__k))
    }

    //--------------------------------------------------------------------------
    pure def isEmpty(__set: Set[a]): bool =
        __set == Set()

    pure def nonEmpty(__set: Set[a]): bool =
        __set != Set()

    //--------------------------------------------------------------------------
    /// Update a map entry using the previous value.
    ///
    /// @param __map the map to update
    /// @param __key the key to search for
    /// @param __f a function that returns the new value for __key 
    ///   when applied to __key's old value
    /// @returns a new map equal to __map except that __key maps
    ///   to __f applied to __key's old value
    pure def mapPut(__map: a -> b, __key: a, __f: b => b): (a -> b) = 
        __map.put(__key, __f(__map.get(__key)))
}