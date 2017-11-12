{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE PartialTypeSignatures #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Data.Geometry.PlanarSubdivision.Core( VertexId', FaceId'
                                           , VertexData(VertexData), PG.vData, PG.location

                                           , EdgeType(..)
                                           , EdgeData(EdgeData), edgeType, eData

                                           , FaceData(FaceData), holes, fData

                                           , PlanarSubdivision(PlanarSubdivision)
                                           , planeGraph
                                           , PolygonFaceData(..)
                                           , PlanarGraph
                                           , fromSimplePolygon, fromConnectedSegments

                                           , numVertices, numEdges, numFaces, numDarts
                                           , dual

                                           , vertices', vertices
                                           , edges', edges
                                           , faces', faces, internalFaces
                                           , darts'

                                           , headOf, tailOf, PG.twin, endPoints, edgeTypeOf

                                           , incidentEdges, incomingEdges, outgoingEdges
                                           , neighboursOf

                                           , leftFace, rightFace
                                           , boundary, boundaryVertices, holesOf
                                           , outerFaceId

                                           , locationOf, vDataOf

                                           , eDataOf, endPointsOf, endPointData
                                           , fDataOf

                                           , edgeSegment, edgeSegments
                                           , rawFacePolygon, rawFaceBoundary
                                           , rawFacePolygons

                                           , VertexId(..), FaceId(..), Dart, World(..)
                                           ) where

import           Control.Lens hiding (holes, holesOf, (.=))
import           Data.Aeson
import           Data.Ext
import           Data.Geometry.LineSegment
import           Data.Geometry.Box
import           Data.Geometry.Properties
import           Data.Geometry.Point
import           Data.Geometry.Polygon
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.PlaneGraph as PG
import           Data.PlaneGraph( PlaneGraph, PlanarGraph, dual
                                , Dart, VertexId(..), FaceId(..)
                                , World(..)
                                , VertexId', FaceId'
                                , VertexData(..)
                                )
import qualified Data.Vector as V
import           GHC.Generics (Generic)


--------------------------------------------------------------------------------

-- | Planar-subdivsions are internally represented as an *connected* plane
-- graph. We distuinish two types of edges in this graph representation:
-- Visible edges, which also appear in the original planar subdivision, and
-- Invisible edges, which are essentially dummy edges making sure that the
-- entire graph is connected.
data EdgeType = Visible | Invisible deriving (Show,Read,Eq,Ord,Generic)

instance FromJSON EdgeType
instance ToJSON EdgeType where
  toEncoding = genericToEncoding defaultOptions


data EdgeData e = EdgeData { _edgeType :: !EdgeType
                           , _eData    :: !e
                           } deriving (Show,Eq,Ord,Functor,Foldable,Traversable,Generic)
makeLenses ''EdgeData

instance FromJSON e => FromJSON (EdgeData e)
instance ToJSON e => ToJSON (EdgeData e) where
  toEncoding = genericToEncoding defaultOptions

-- | The Face data consists of the data itself and a list of holes
data FaceData h f = FaceData { _holes :: [h]
                             , _fData :: !f
                             } deriving (Show,Eq,Ord,Functor,Foldable,Traversable,Generic)
makeLenses ''FaceData

instance (FromJSON h, FromJSON f) => FromJSON (FaceData h f)
instance (ToJSON h, ToJSON f)     => ToJSON (FaceData h f) where
  toEncoding = genericToEncoding defaultOptions


--------------------------------------------------------------------------------
-- * The Planar Subdivision Type

newtype PlanarSubdivision s v e f r = PlanarSubdivision { _planeGraph ::
    PlaneGraph s v (EdgeData e) (FaceData (Dart s) f) r}
      deriving (Show,Eq,Functor)
makeLenses ''PlanarSubdivision

type instance NumType   (PlanarSubdivision s v e f r) = r
type instance Dimension (PlanarSubdivision s v e f r) = 2

instance IsBoxable (PlanarSubdivision s v e f r) where
  boundingBox = boundingBox . _planeGraph


-- instance (ToJSON v, ToJSON e, ToJSON f, ToJSON r)
--          => ToJSON (PlanarSubdivision s v e f r) where
--   toJSON ps = object [ "vertices"    .= (fmap (\(v,d) -> v :+ d) . vertices $ ps)
--                      , "edges"       .= (fmap (\(e,d) -> e :+ d) . edges    $ ps)
--                      , "faces"       .= (fmap (\(f,d) -> f :+ d) . faces    $ ps)
--                      , "adjacencies" .= PG.toAdjacencyLists (ps^.graph)
--                      ]
--     where

--       showVtx ()

--------------------------------------------------------------------------------
-- * Constructing a planar subdivision

-- | Data type that expresses whether or not we are inside or outside the
-- polygon.
data PolygonFaceData = Inside | Outside deriving (Show,Read,Eq)

-- | Construct a planar subdivision from a simple polygon
--
-- running time: \(O(n)\).
fromSimplePolygon                            :: proxy s
                                             -> SimplePolygon p r
                                             -> f -- ^ data inside
                                             -> f -- ^ data outside the polygon
                                             -> PlanarSubdivision s p () f r
fromSimplePolygon p pg iD oD = PlanarSubdivision . f $ PG.fromSimplePolygon p pg iD oD
  where
    f g = g & PG.faceData.traverse    %~ FaceData []
            & PG.dartData.traverse._2 .~ EdgeData Visible ()

-- | Constructs a connected planar subdivision.
--
-- pre: the segments form a single connected component
-- running time: \(O(n\log n)\)
fromConnectedSegments       :: (Foldable f, Ord r, Num r)
                            => proxy s
                            -> f (LineSegment 2 p r :+ EdgeData e)
                            -> PlanarSubdivision s (NonEmpty.NonEmpty p) e () r
fromConnectedSegments px ss = PlanarSubdivision $
    PG.fromConnectedSegments px ss & PG.faceData.traverse %~ FaceData []

--------------------------------------------------------------------------------
-- * Basic Graph information

-- | Get the number of vertices
--
-- >>> numVertices myGraph
-- 4
numVertices :: PlanarSubdivision s v e f r  -> Int
numVertices = PG.numVertices . _planeGraph

-- | Get the number of Darts
--
-- >>> numDarts myGraph
-- 12
numDarts :: PlanarSubdivision s v e f r  -> Int
numDarts = PG.numDarts . _planeGraph

-- | Get the number of Edges
--
-- >>> numEdges myGraph
-- 6
numEdges :: PlanarSubdivision s v e f r  -> Int
numEdges = PG.numEdges . _planeGraph

-- | Get the number of faces
--
-- >>> numFaces myGraph
-- 4
numFaces :: PlanarSubdivision s v e f r  -> Int
numFaces = error "not implemented yet"
--FIXME!!


-- | Enumerate all vertices
--
-- >>> vertices' myGraph
-- [VertexId 0,VertexId 1,VertexId 2,VertexId 3]
vertices'   :: PlanarSubdivision s v e f r  -> V.Vector (VertexId' s)
vertices' = PG.vertices' . _planeGraph

-- | Enumerate all vertices, together with their vertex data

-- >>> vertices myGraph
-- [(VertexId 0,()),(VertexId 1,()),(VertexId 2,()),(VertexId 3,())]
vertices   :: PlanarSubdivision s v e f r  -> V.Vector (VertexId' s, VertexData r v)
vertices = PG.vertices . _planeGraph

-- | Enumerate all darts
darts' :: PlanarSubdivision s v e f r  -> V.Vector (Dart s)
darts' = PG.darts' . _planeGraph

-- | Enumerate all edges. We report only the Positive darts
edges' :: PlanarSubdivision s v e f r  -> V.Vector (Dart s)
edges' = PG.edges' . _planeGraph

-- | Enumerate all edges with their edge data. We report only the Positive
-- darts.
--
-- >>> mapM_ print $ edges myGraph
-- (Dart (Arc 2) +1,"c+")
-- (Dart (Arc 1) +1,"b+")
-- (Dart (Arc 0) +1,"a+")
-- (Dart (Arc 5) +1,"g+")
-- (Dart (Arc 4) +1,"e+")
-- (Dart (Arc 3) +1,"d+")
edges :: PlanarSubdivision s v e f r  -> V.Vector (Dart s, EdgeData e)
edges = PG.edges . _planeGraph

-- | Enumerate all faces in the planar subdivision
faces' :: PlanarSubdivision s v e f r  -> V.Vector (FaceId' s)
faces' = error "not implemented"

-- | All faces with their face data.
faces :: PlanarSubdivision s v e f r  -> V.Vector (FaceId' s, FaceData (Dart s) f)
faces = error "not implemented"

-- | Enumerates all faces with their face data exlcluding  the outer face
internalFaces    :: (Ord r, Fractional r) => PlanarSubdivision s v e f r
                 -> V.Vector (FaceId' s, FaceData (Dart s) f)
internalFaces ps = let i = outerFaceId ps
                 in V.filter (\(j,_) -> i /= j) $ faces ps

-- | The tail of a dart, i.e. the vertex this dart is leaving from
--
-- running time: \(O(1)\)
tailOf   :: Dart s -> PlanarSubdivision s v e f r  -> VertexId' s
tailOf d = PG.tailOf d . _planeGraph

-- | The vertex this dart is heading in to
--
-- running time: \(O(1)\)
headOf   :: Dart s -> PlanarSubdivision s v e f r  -> VertexId' s
headOf d = PG.headOf d . _planeGraph

-- | endPoints d g = (tailOf d g, headOf d g)
--
-- running time: \(O(1)\)
endPoints   :: Dart s -> PlanarSubdivision s v e f r
            -> (VertexId' s, VertexId' s)
endPoints d = PG.endPoints d . _planeGraph

edgeTypeOf   :: Dart s -> Lens' (PlanarSubdivision s v e f r ) EdgeType
edgeTypeOf d = planeGraph.PG.eDataOf d.edgeType

-- | All edges incident to vertex v, in counterclockwise order around v.

-- TODO: filter invisible edges
--
-- running time: \(O(k)\), where \(k\) is the output size
incidentEdges   :: VertexId' s -> PlanarSubdivision s v e f r -> V.Vector (Dart s)
incidentEdges v = PG.incidentEdges v . _planeGraph



-- | All incoming edges incident to vertex v, in counterclockwise order around v.
incomingEdges   :: VertexId' s -> PlanarSubdivision s v e f r -> V.Vector (Dart s)
incomingEdges v = PG.incomingEdges v . _planeGraph

-- | All outgoing edges incident to vertex v, in counterclockwise order around v.
outgoingEdges   :: VertexId' s -> PlanarSubdivision s v e f r  -> V.Vector (Dart s)
outgoingEdges v = PG.outgoingEdges v . _planeGraph

-- | Gets the neighbours of a particular vertex, in counterclockwise order
-- around the vertex.
--
-- running time: \(O(k)\), where \(k\) is the output size
neighboursOf   :: VertexId' s -> PlanarSubdivision s v e f r
               -> V.Vector (VertexId' s)
neighboursOf v = PG.neighboursOf v . _planeGraph

-- | The face to the left of the dart
--
-- >>> leftFace (dart 1 "+1") myGraph
-- FaceId 1
-- >>> leftFace (dart 1 "-1") myGraph
-- FaceId 2
-- >>> leftFace (dart 2 "+1") myGraph
-- FaceId 2
-- >>> leftFace (dart 0 "+1") myGraph
-- FaceId 0
--
-- running time: \(O(1)\).
leftFace   :: Dart s -> PlanarSubdivision s v e f r  -> FaceId' s
leftFace d = PG.leftFace d . _planeGraph

-- | The face to the right of the dart
--
-- >>> rightFace (dart 1 "+1") myGraph
-- FaceId 2
-- >>> rightFace (dart 1 "-1") myGraph
-- FaceId 1
-- >>> rightFace (dart 2 "+1") myGraph
-- FaceId 1
-- >>> rightFace (dart 0 "+1") myGraph
-- FaceId 1
--
-- running time: \(O(1)\).
rightFace   :: Dart s -> PlanarSubdivision s v e f r  -> FaceId' s
rightFace d = PG.rightFace d . _planeGraph


-- | The darts bounding this face, for internal faces in clockwise order, for
-- the outer face in counter clockwise order.
--
--
-- running time: \(O(k)\), where \(k\) is the output size.
boundary   :: FaceId' s -> PlanarSubdivision s v e f r  -> V.Vector (Dart s)
boundary f = PG.boundary f . _planeGraph


-- | The vertices bounding this face, for internal faces in clockwise order, for
-- the outer face in counter clockwise order.
--
--
-- running time: \(O(k)\), where \(k\) is the output size.
boundaryVertices   :: FaceId' s -> PlanarSubdivision s v e f r
                   -> V.Vector (VertexId' s)
boundaryVertices f = PG.boundaryVertices f . _planeGraph


-- | Lists the holes in this face, given as a list of darts to arbitrary darts
-- on those faces.
--
-- running time: \(O(k)\), where \(k\) is the number of darts returned.
holesOf   :: FaceId' s -> PlanarSubdivision s v e f r -> [Dart s]
holesOf f = view (planeGraph.PG.fDataOf f.holes)

--------------------------------------------------------------------------------
-- * Access data


locationOf   :: VertexId' s -> Lens' (PlanarSubdivision s v e f r ) (Point 2 r)
locationOf v = planeGraph.PG.locationOf v

-- | Get the vertex data associated with a node. Note that updating this data may be
-- expensive!!
--
-- running time: \(O(1)\)
vDataOf   :: VertexId' s -> Lens' (PlanarSubdivision s v e f r) v
vDataOf v = planeGraph.PG.vDataOf v

-- | Edge data of a given dart
--
-- running time: \(O(1)\)
eDataOf   :: Dart s -> Lens' (PlanarSubdivision s v e f r ) e
eDataOf d = planeGraph.PG.eDataOf d.eData

-- | Data of a face of a given face
--
-- running time: \(O(1)\)
fDataOf   :: FaceId' s -> Lens' (PlanarSubdivision s v e f r ) f
fDataOf f = planeGraph.PG.fDataOf f.fData


-- class HasData t v e f r where
--   type DataOf t v e f r
--   dataOf :: t -> Lens' (PlanarSubdivision s v e f r) (DataOf t v e f r)

-- | Getter for the data at the endpoints of a dart
--
-- running time: \(O(1)\)
endPointsOf   :: Dart s -> Getter (PlanarSubdivision s v e f r )
                                  (VertexData r v, VertexData r v)
endPointsOf d = planeGraph.PG.endPointsOf d

-- | Data corresponding to the endpoints of the dart
--
-- running time: \(O(1)\)
endPointData   :: Dart s -> PlanarSubdivision s v e f r
               ->  (VertexData r v, VertexData r v)
endPointData d = PG.endPointData d . _planeGraph

--------------------------------------------------------------------------------

-- | gets the id of the outer face
--
-- running time: \(O(n)\)
outerFaceId :: (Ord r, Fractional r) => PlanarSubdivision s v e f r -> FaceId' s
outerFaceId = PG.outerFaceId . _planeGraph

--------------------------------------------------------------------------------

-- | Reports all visible segments as line segments
edgeSegments :: PlanarSubdivision s v e f r -> [(Dart s, LineSegment 2 v r :+ e)]
edgeSegments = map (\x -> x&_2.extra %~ _eData)
             . filter (\x -> x^._2.extra.edgeType == Visible)
             . PG.edgeSegments . _planeGraph

-- | Given a dart and the subdivision constructs the line segment representing it
--
-- \(O(1)\)
edgeSegment   :: Dart s -> PlanarSubdivision s v e f r -> LineSegment 2 v r :+ e
edgeSegment d = (\x -> x&extra %~ _eData) . PG.edgeSegment d . _planeGraph


-- TODO, This should ignore invisible edges!!!!

rawFaceBoundary   :: FaceId' s -> PlanarSubdivision s v e f r -> SimplePolygon v r :+ f
rawFaceBoundary i = (\x -> x&extra %~ _fData) . PG.rawFaceBoundary i . _planeGraph


rawFacePolygon :: FaceId' s -> PlanarSubdivision s v e f r
                    -> SomePolygon v r :+ f
rawFacePolygon i ps = case holesOf i ps of
                        [] -> Left  res                               :+ x
                        hs -> Right (MultiPolygon vs $ map toHole hs) :+ x
  where
    res@(SimplePolygon vs) :+ x = rawFaceBoundary i ps
    toHole d = (rawFaceBoundary (leftFace d ps) ps)^.core

-- | Lists all faces of the planar graph. This ignores invisible edges
rawFacePolygons    :: PlanarSubdivision s v e f r
                   -> V.Vector (FaceId' s, SomePolygon v r :+ f)
rawFacePolygons ps = fmap (\i -> (i,rawFacePolygon i ps)) . faces' $ ps

--------------------------------------------------------------------------------
-- * Reading and Writing the planar subdivision

--
-- readPlanarSubdivision :: (FromJSON v, FromJSON e, FromJSON f, FromJSON r)
--                           => proxy s -> ByteString
--                          -> Either String (PlanarSubdivision s v e f r)
-- readPlanarSubdivision = undefined--  parseEither


-- writePlanarSubdivision :: (ToJSON v, ToJSON e, ToJSON f, ToJSON r)
--                           => PlanarSubdivision s v e f r -> ByteString
-- writePlanarSubdivision = YamlP.encodePretty YamlP.defConfig
