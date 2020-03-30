{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}
module Data.Geometry.QuadTree where

import           Control.Lens (makeLenses,makePrisms,(^.),(.~),(%~),(&),(^?!),(^@.),ix,iix,view)
-- import           Control.Zipper
import           Data.Bifoldable
import           Data.Bifunctor
import           Data.BinaryTree (RoseElem(..))
import           Data.Bitraversable
import           Data.Ext
import qualified Data.Foldable as F
import           Data.Functor.Apply
import           Data.Geometry.Box
import           Data.Geometry.LineSegment
import           Data.Geometry.Point
import           Data.Geometry.Vector
import           Data.Intersection
import qualified Data.List as List
import           Data.List.NonEmpty (NonEmpty(..))
import qualified Data.List.NonEmpty as NonEmpty
import           Data.Semigroup.Foldable.Class
import           Data.Semigroup.Traversable.Class
import qualified Data.Sequence as Seq
import qualified Data.Tree as RoseTree
import           Debug.Trace
import           GHC.Generics (Generic)
import           Data.Geometry.QuadTree.Cell
import           Data.Geometry.QuadTree.Quadrants
import           Data.Geometry.QuadTree.Tree (Tree(..))
import qualified Data.Geometry.QuadTree.Tree as Tree
import           Data.Geometry.QuadTree.Split


import           Debug.Trace

--------------------------------------------------------------------------------

-- data Quadrants a b c d = Quadrants { _northEast  :: a
--                                    , _southEast  :: b
--                                    , _southWest  :: c
--                                    , _northWest  :: d
--                                    } deriving (Show,Eq,Ord,Generic)
-- type Quadrants' a = Quadrants a a a a

-- qMap f g h i (Quadrants a b c d) = Quadrants (f a) (g b) (h c) (i d)


--------------------------------------------------------------------------------
--


--------------------------------------------------------------------------------
           --
-- | Subdiv of the area from [0,2^w] x [0,2^w]
data QuadTree v p = QuadTree { _boxWidthIndex :: WidthIndex
                             , _tree          :: Tree v p
                             }
                  deriving (Show,Eq)
makeLenses ''QuadTree

--------------------------------------------------------------------------------
-- * Functions operating on the QuadTree (in terms of the 'Tree' type)

withCells    :: QuadTree v p -> QuadTree (v :+ Cell) (p :+ Cell)
withCells qt = qt&tree .~ withCellsTree qt

withCellsTree                :: QuadTree v p -> Tree (v :+ Cell) (p :+ Cell)
withCellsTree (QuadTree w t) = Tree.withCells (Cell w origin) t

leaves :: QuadTree v p -> NonEmpty p
leaves = Tree.leaves . view tree

--------------------------------------------------------------------------------

-- | Builds a QuadTree
build     :: (Cell -> i -> Split i v p) -> Cell -> i -> QuadTree v p
build f c = QuadTree (c^.cellWidthIndex) . Tree.build f c


-- | Build a QuadtTree from a set of points.
--
-- pre: the points lie inside the initial given cell.
--
-- running time: \(O(nh)\), where \(n\) is the number of points and
-- \(h\) is the height of the resulting quadTree.
fromPoints   :: (Num r, Ord r) => Cell -> [Point 2 r :+ p] -> QuadTree () (Maybe (Point 2 r :+ p))
fromPoints c = QuadTree (c^.cellWidthIndex) . Tree.fromPoints c


-- | Locates the cell containing the given point, if it exists.
--
-- running time: \(O(h)\), where \(h\) is the height of the quadTree
findLeaf                                       :: (Num r, Ord r)
                                               => Point 2 r -> QuadTree v p -> Maybe (p :+ Cell)
findLeaf q (QuadTree w t) | q `intersects` c0  = Just $ findLeaf' c0 t
                          | otherwise          = Nothing
  where
    c0 = Cell w origin
    -- |
    -- pre: p intersects c
    findLeaf' c = \case
      Leaf p    -> p :+ c
      Node _ qs -> let quad = quadrantOf q c
                   in findLeaf' ((splitCell c)^?!ix quad) (qs^?!ix quad)

--------------------------------------------------------------------------------


fromZeros :: (Num a, Eq a, v ~ Quadrants Sign)
          => Cell -> (Point 2 R -> a) -> QuadTree v (Either v Sign)
fromZeros = fromZerosWith (limitWidthTo 0)


fromZerosWith           :: (Num a, Eq a, v ~ Quadrants Sign, p ~ Sign, i ~ v)
                        => (  (Cell -> i -> Split i v p)
                           -> (Cell -> i -> Split i v (Either i p))
                           )
                        -> Cell -> (Point 2 R -> a) -> QuadTree (Quadrants Sign) (Either i p)
fromZerosWith limit c0 f = QuadTree (c0^.cellWidthIndex)
                        $ Tree.build (limit $ shouldSplitZeros f') c0 (f' <$> cellCorners c0)
  where
    f' = fromSignum f




data Sign = Negative | Zero | Positive deriving (Show,Eq,Ord)

fromSignum   :: (Num a, Eq a) => (b -> a) -> b -> Sign
fromSignum f = \x -> case signum (f x) of
                       -1 -> Negative
                       0  -> Zero
                       1  -> Positive
                       _  -> error "absurd: fromSignum"



shouldSplitZeros :: (Point 2 R -> Sign) -- ^ The function we are evaluating
                 -> Cell
                 -> Quadrants Sign -- ^ signs of the corners
                 -> Split (Quadrants Sign) -- ^ to compute further signs we use signs
                          (Quadrants Sign) -- ^ we store the signs of the corners
                          Sign             -- ^ Leaves store the sign corresponding to the leaf
shouldSplitZeros f (Cell w' p) qs@(Quadrants nw ne se sw) | all sameSign qs = No ne
                                                          | otherwise       = Yes qs qs'
  where
    m = fAt rr rr
    n = fAt rr ww
    e = fAt ww rr
    s = fAt rr 0
    w = fAt 0  rr

    sameSign = (== ne)

    -- signs at the new corners
    qs' = Quadrants (Quadrants nw n m w)
                    (Quadrants n ne e m)
                    (Quadrants m e se s)
                    (Quadrants w m s sw)

    r     = w' - 1
    rr    = 2 ^ r
    ww    = 2 ^ w'

    fAt x y = f $ p .+^ Vector2 x y





isZeroCell :: Either v Sign -> Bool
isZeroCell = \case
    Left _  -> True -- if we kept splitting then we must have a sign transition
    Right s -> s == Zero





withNeighbours    :: [p :+ Cell] -> [(p :+ Cell) :+ Sides [p :+ Cell]]
withNeighbours cs = map (\c@(_ :+ me) -> c :+ neighboursOf me) cs
  where
    -- neighboursOf me = fmap mconcat $ traverse (`relationTo` me) cs
    neighboursOf me = foldMap (`relationTo` me) cs



leafNeighboursOf   :: Cell -> QuadTree v p -> Sides [p :+ Cell]
leafNeighboursOf c = neighboursOf c . Tree.leaves . withCellsTree
  where
    neighboursOf me = foldMap (`relationTo` me)


exploreWith               :: forall p. Eq p
                          => (p :+ Cell -> Bool) -- ^ continue exploring?
                          -> p :+ Cell -- ^ start
                          -> [p :+ Cell] -- ^ all cells
                          -> RoseTree.Tree (p :+ Cell)
exploreWith p start' cells = go0 start'
  where
    cs   :: [(p :+ Cell) :+ Sides [p :+ Cell]]
    cs   = withNeighbours cells

    -- initially, just explore everyone
    go0      c = RoseTree.Node c [ go c n | n <- neighboursOf c, p n ]

    -- explore only the nodes other than the one we just came from
    go pred' c = RoseTree.Node c [ go c n | n <- neighboursOf c, continue pred' n ]

    continue pred' n = n /= pred' && p n

    neighboursOf   :: p :+ Cell -> [p :+ Cell]
    neighboursOf c = case List.find (\n -> n^.core == c) cs of
                       Nothing       -> []
                       Just (_ :+ s) -> concat s


explorePathWith          :: Eq p
                         => ((p :+ Cell) -> Bool)
                         -> (p :+ Cell) -> [p :+ Cell] -> NonEmpty (p :+ Cell)
explorePathWith p start' = toPath . exploreWith p start'
  where
    toPath (RoseTree.Node x chs) = ($ x ) $ case chs of
                                              []    -> (:| [])
                                              (c:_) -> (NonEmpty.<| toPath c)






-- trace             :: Cell -> [p :+ Cell] -> [p :+ Cell]
-- trace start cells = go0 start'
--   where
--     cs     = withNeighbours cs
--     start' = find (\c -> c^.extra == start) cs

--     go0 = undefined
--     go p (s :+ neighs) = case find (\c -> ) neighs

--     ( s:+ ) =

--       \case
--       Nothing            -> []
--       Just (s :+ neighs) -> s : go (otherN)
--     go1 s =





relationTo        :: (p :+ Cell) -> Cell -> Sides [p :+ Cell]
c `relationTo` me = f <$> Sides b l t r <*> cellSides me
  where
    Sides t r b l = cellSides (c^.extra)
    f e e' | e `sideIntersects` e' = [c]
           | otherwise             = []

    sa `sideIntersects` sb = (toRat <$> sa) `intersects` (toRat <$> sb)
    toRat :: Int -> Rational
    toRat = realToFrac

-- eastNeighbours    :: [p :+ Cell] -> [(p :+ Cell) :+ [p :+ Cell]]
-- eastNeighbours cs = map (\(_ :+ c) -> Map.lookup c ns) cs
--   where






--------------------------------------------------------------------------------



-- neighbours   :: _ :> zipper -> [zipper]
-- neighbours z = upwards


-- test :: Top :> (Quadrants a :@ Directions) a
-- test = zipper (Quadrants _ _ _ _) & downward northEast

-- data TZ a = TZ { _focus            :: RoseTree.Tree a
--                , _leftSiblings     :: [RoseTree.Tree a]
--                , _rightSiblings    :: [RoseTree.Tree a]
--                , _parent           :: Maybe (TZ a)
--                }

-- toRoot t = TZ t [] [] Nothing2

-- toFirstChild :: TZ a -> Maybe (TZ a)
-- toFirstChild z@(TZ (RoseTree.Node _ chs) _ _ _) = case chs of
--                                                       []       -> Nothing
--                                                       (c:chs') -> Just $ TZ c [] chs' (Just z)




-- toParent (TZ t ls rs mp) = case mp of
--     Nothing -> Nothing
--     Just (TZ x als ars mg) -> Just
--                            $ TZ (RoseTree.Node (root x) (reverse ls <> [t] <> rs)) als ars mg
--   where
--     root (RoseTree.Node x _) = x
