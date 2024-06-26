// -*- mode: Bluespec; -*-
module spells {

    //--------------------------------------------------------------------------
    // Basic
    //--------------------------------------------------------------------------

    /// An annotation for writing preconditions.
    pure def require(__cond: bool): bool = __cond

    //--------------------------------------------------------------------------
    // Options
    //--------------------------------------------------------------------------

    type Option[a] =
        | Some(a)
        | None

    pure def isSome(__opt) =
        match __opt {
        | Some(_) => true
        | None => false
        }

    pure def isNone(__opt) = not(isSome(__opt))

    pure def optionGet(__opt) =
        match __opt {
        | Some(a) => a
        | None => Set()
        }

    // pure def optionValues(__opt) =
    //     match __opt {
    //     | Some(a) => Set(a)
    //     | None => Set()
    //     }

    pure def optionMap(__opt: Option[a], __f: a => b): Option[b] =
        match __opt {
        | Some(a) => Some(__f(a))
        | None => None
        }

    pure def optionFlatten(__opt: Option[Option[a]]): Option[a] =
        match __opt {
        | Some(o) => o
        | None => None
        }

    pure def optionListToList(__opt: Option[List[a]]): List[a] =
        match __opt {
        | Some(l) => l
        | None => List()
        }

    //--------------------------------------------------------------------------
    // Sets
    //--------------------------------------------------------------------------

    pure def setAdd(__set: Set[a], __elem: a): Set[a] =
        __set.union(Set(__elem))

    pure def isEmpty(__set: Set[a]): bool =
        __set == Set()

    pure def nonEmpty(__set: Set[a]): bool =
        not(__set.isEmpty())

    //--------------------------------------------------------------------------
    // Maps
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

    pure def mapPut2(__map: a -> b -> c, __key1: a, __key2: b, __default: c, __f: c => c): (a -> b -> c) = 
        __map.mapPut(__key1, __m => __m.put(__key2, 
            val v = if (__m.keys().contains(__key2)) __m.get(__key2) else __default
            __f(v)))

    /// Update a set of map entries.
    ///
    /// @param __map the map to update
    /// @param __keys the set of keys to be updated in __map
    /// @param __values a function that returns the value for a key in __keys
    /// @returns a new map equal to __map except that for each key k in __keys 
    ///   will map to __values(k)
    pure def mapPutMany(__map: a -> b, __keys: Set[a], __values: a => b): (a -> b) = 
        __map.keys().union(__keys).mapBy(k => if (k.in(__keys)) __values(k) else __map.get(k))

    pure def mapRemoveMultiple(__map: a -> b, __keys: Set[a]): (a -> b) = 
        __map.keys().filter(k => not(k.in(__keys))).mapBy(k => __map.get(k))

    pure def mapRemove(__map: a -> b, __key: a): (a -> b) = 
        mapRemoveMultiple(__map, Set(__key))

    pure def mapGetSafe(__map: a -> b, x: a): Option[b] = 
        if (__map.keys().contains(x)) Some(__map.get(x)) else None

    //--------------------------------------------------------------------------
    // Lists
    //--------------------------------------------------------------------------

    pure def listIsEmpty(__list: List[a]): bool =
        __list == List()

    pure def listToSet(__list: List[a]): Set[a] =
        __list.foldl(Set(), (__s, __x) => __s.setAdd(__x))

    pure def setToList(__set: Set[a]): List[a] =
        __set.fold(List(), (__l, __x) => __l.append(__x))

    pure def includes(__list: List[a], x: a): bool =
        __list.listToSet().contains(x)

    pure def headOption(__list: List[a]): Option[a] =
        if (__list.length() > 0) Some(__list.head()) else None

}