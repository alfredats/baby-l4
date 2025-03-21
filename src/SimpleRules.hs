{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE TupleSections #-}

module SimpleRules where

import L4.Syntax
import qualified Data.Set as S
import Data.Graph.Inductive.Graph
import Data.Graph.Inductive.PatriciaTree ( Gr )
import qualified Data.Maybe as M
import qualified Data.List as L
import Data.GraphViz
import Data.Graph.Inductive.Query.DFS

import Data.GraphViz.Attributes.Complete
import qualified Data.Text.Lazy as T
import Data.Either
        -- usefulrules = ["accInad", "accAdIncAd", "accAdIncInad", "savingsAd", "savingsInad", "incomeAd", "incomeInadESteady", "incomeInadEUnsteady"]
        -- usefulsimple = [r | r <- validRules , nameOfSimpleRule r `elem` usefulrule

data SimpleRule t = SimpleRule {
                     nameOfSimpleRule :: String -- Maybe String
                   , varDeclsOfSimpleRule :: [VarDecl t]
                   , precondOfSimpleRule :: [Expr t]
                   , postcondOfSimpleRule :: Expr t }
  deriving (Eq, Ord, Show, Read, Functor)

-- Helper function that determines if a rule structure is a predicate
isRule :: Rule t -> Bool
isRule x
  | condValid (precondOfRule x) && condValid (postcondOfRule x) = True -- do i need to check if the rule has a name?
  | otherwise = False

-- Helper function for checking valid pre/post-condition
condValid :: Expr t -> Bool
condValid x = case x of
  BinOpE _ (BBool BBand) e1 e2-> condValid e1 || condValid e2
  AppE {} -> True
  _ -> False

-- Helper function to extract useful expressions within conjunctions
flattenConjs :: Expr t -> [Expr t]
flattenConjs (BinOpE _ (BBool BBand) e1 e2) = flattenConjs e1 <> flattenConjs e2
flattenConjs fApp@AppE {} = [fApp]
flattenConjs _ = []

-- TODO 1: some sort of preprocesing that removes illegal expressions (not applications of predicates to arguments)
-- DONE, to review
--    a note: isRule filters the rules that need processing, flattenConjs filters & processes the conjugates of said rules
ruleToSimpleRule :: Rule t -> Either String (SimpleRule t)
ruleToSimpleRule r
  | isRule r = Right $ SimpleRule
                        (M.fromJust $ nameOfRule r)
                        (varDeclsOfRule r)
                        (flattenConjs (precondOfRule r))
                        (postcondOfRule r)
  | otherwise = Left $ "Not a valid rule: " ++ M.fromJust (nameOfRule r) ++ "\n"


type PredName = String
type RuleName = String

data GrNode =
    PredOr PredName -- implicit Or
  | RuleAnd RuleName -- implicit And
  deriving (Eq, Ord, Show)

type GrEdge = (GrNode, GrNode)

instance Labellable GrNode where
  toLabelValue :: GrNode -> Label
  toLabelValue x = StrLabel (T.pack $ show x)

-- implicit Or
mkPredRule :: [SimpleRule t] -> PredName -> S.Set GrEdge
mkPredRule xs pname =
  let matchedRuleNames = [RuleAnd $ nameOfSimpleRule r | r <- xs, (funNameOfApp . postcondOfSimpleRule) r == Just pname]
  in S.fromList $ map (PredOr pname,) matchedRuleNames

-- implicit And
mkRulePred :: SimpleRule t -> S.Set GrEdge
mkRulePred r =
  let rname = nameOfSimpleRule r
      preConds = precondOfSimpleRule r
      preCondName = M.mapMaybe funNameOfApp preConds
  in S.fromList $ map ((RuleAnd rname,) . PredOr) preCondName


simpleRulesToGrNodes :: [SimpleRule t] -> (S.Set GrNode, S.Set GrEdge)
simpleRulesToGrNodes xs = let
  prednames = getAllRulePreds xs      -- prednames : Set PredName         -- we don't want duplicate predicate names
  rulenames = getAllRuleNames xs      -- rulenames : Set Rulename         -- no duplicate 
  prednodes = S.map PredOr prednames    -- prednodes : Set GrNode
  rulenodes = S.map RuleAnd rulenames   -- rulenodes : Set GrNode
  orruleedges = S.unions $ S.map (mkPredRule xs) prednames    -- orruleedges: Set GrEdge
  andprededges = S.unions $ map mkRulePred xs
  in
  (S.unions [prednodes,rulenodes],
   S.unions [andprededges, orruleedges])

simpleRuleToGrNodes :: SimpleRule t -> (S.Set GrNode, S.Set GrEdge)
simpleRuleToGrNodes r = let
  (preconds, postcond) = rulePreds' r
  rulename = nameOfSimpleRule r      -- rulenames : String
  precondnodes = S.map PredOr preconds -- prednodes : Set GrNode
  postcondnode = PredOr postcond
  rulenode = RuleAnd rulename   -- rulenodes : Set GrNode
  orruleedges = (postcondnode, rulenode) -- orruleedges: Set GrEdge
  andprededges = S.map (rulenode, ) precondnodes
  in
  (S.union precondnodes $ S.fromList [postcondnode, rulenode],
   S.union andprededges $ S.singleton orruleedges)


getAllRulePreds :: [SimpleRule t] -> S.Set PredName
getAllRulePreds xs = S.unions $ map rulePreds xs

rulePreds :: SimpleRule t -> S.Set PredName
rulePreds (SimpleRule _ _ preConds postConds) = S.fromList $ M.mapMaybe funNameOfApp (postConds : preConds)

rulePreds' :: SimpleRule t -> (S.Set PredName, PredName)
rulePreds' (SimpleRule _ _ preConds postConds) =
  ( S.fromList . M.mapMaybe funNameOfApp $ preConds
  , M.fromJust . funNameOfApp $ postConds )

funNameOfApp :: Expr t -> Maybe PredName
funNameOfApp (AppE _ x _) = funNameOfApp x
funNameOfApp (VarE _ x) = Just $ nameOfQVarName $ nameOfVar x
funNameOfApp _ = Nothing


getAllRuleNames :: [SimpleRule t] -> S.Set RuleName
getAllRuleNames xs = S.fromList $ map nameOfSimpleRule xs

type NInd = Int
-- a is the node type
data LabelledGraph a = LG (Gr a String) [(NInd, a)] [(a, NInd)]
  deriving Show

data GraphOut = Dependency | Propagation deriving (Eq, Show)


mkPropagationGraph :: Eq a => S.Set a -> S.Set (a, a) -> LabelledGraph a
mkPropagationGraph = mkLabelledGraph Propagation

mkDependencyGraph :: Eq a => S.Set a -> S.Set (a, a) -> LabelledGraph a
mkDependencyGraph = mkLabelledGraph Dependency


-- | Makes either a propagation or dependency graph
-- a ~ GrNode
mkLabelledGraph :: Eq a => GraphOut -> S.Set a -> S.Set (a, a) -> LabelledGraph a
mkLabelledGraph gOut nodeset edgeset =
  let nodelist = S.toList nodeset
      edgelist = S.toList edgeset
      nodeIndSym = zip [0..length nodelist-1] nodelist
      nodeSymInd = zip nodelist [0..length nodelist-1]
      gEdges = edgeSetSymToInd gOut nodeSymInd edgelist
  in LG (mkGraph nodeIndSym gEdges) nodeIndSym nodeSymInd

-- fromJust: whatever that is queried (NInd/Sym) should occur in assoc list
-- | Given a list of [(Nind, Sym)]/[(Sym,Nind)] and a Nind/Sym to query, returns Sym/Nind
bidirLookup :: Eq a => [(a, b)] -> a -> b
bidirLookup xs a = M.fromJust $ L.lookup a xs

edgeSetSymToInd :: Eq a => GraphOut -> [(a, NInd)] -> [(a, a)] -> [(NInd, NInd, String)]
edgeSetSymToInd Propagation nodeSymInd = map (\(n1,n2) -> (bidirLookup nodeSymInd n2, bidirLookup nodeSymInd n1, ""))
edgeSetSymToInd Dependency nodeSymInd = map (\(n1,n2) -> (bidirLookup nodeSymInd n1, bidirLookup nodeSymInd n2, ""))

labelledSCC :: LabelledGraph a -> [[a]]
labelledSCC (LG gr indSym _) = map (map (bidirLookup indSym)) (scc gr)


-- TODO 4
-- topologically sort graph beginning from leaves
-- find min and max dependency of each node
expSys :: Program (Tp ()) -> IO ()
expSys x = do
    let myrules = rulesOfProgram x
        errs = lefts $ map ruleToSimpleRule myrules
        validRules = rights $ map ruleToSimpleRule myrules
        (usnodes, usedges) = simpleRulesToGrNodes validRules
        myPropLGGraph = mkLabelledGraph Propagation usnodes usedges
        myDepLGGraph = mkLabelledGraph Dependency usnodes usedges
        (LG mypropgraph _ siprop) = myPropLGGraph
        (LG mydepgraph _ sidep) = myDepLGGraph
        sortedNodes = topsort' mypropgraph
        annotsMax = propagate myDepLGGraph sortedNodes Max []
        annotsMin = propagate myDepLGGraph sortedNodes Min []
    _ <- runGraphviz (graphToDot quickParams mypropgraph) Pdf "compactPropGraph.pdf"
    _ <- runGraphviz (graphToDot quickParams mydepgraph) Pdf "compactDepGraph.pdf"
    print $ topsort' mypropgraph
    -- print errs
    -- print validRules
    print $ suc mypropgraph (bidirLookup siprop $ PredOr "earnings")
    print $ suc mydepgraph (bidirLookup sidep $ PredOr "earnings")
    putStrLn $ "max graph: " ++ show (propagate myDepLGGraph sortedNodes Max []) -- Note that we are using the dep graph as the "context", but the topologically sorted list from the prop graph as the "queue"
    putStrLn $ "min graph: " ++ show (propagate myDepLGGraph sortedNodes Min [])
        -- print $ labelledSCC mypropgraph
        -- return ()

    -- putStrLn $ "min savings_account " ++ show (annotateMin (PredOr "savings_account") myDepLGGraph annotsMin)
    -- putStrLn $ "max savings_account " ++ show (annotateMax (PredOr "savings_account") myDepLGGraph annotsMax)

data Annot = Min | Max deriving Show

propagate :: LabelledGraph GrNode -- dependency graph
          -> [GrNode] -- topologically sorted list of nodes as symbols from propagation graph
          -> Annot
          -> [(GrNode, S.Set GrNode)] -- interim assoc list of each node and its annotation
          -> [(GrNode, S.Set GrNode)] -- final assoc list of each node and its annotation
-- a node's annotation is the set of all reachable leaf preds
propagate _ [] _ assoc = assoc                                            -- when the queue is complete, return association list
propagate gr (x:xs) annot assoc = propagate gr xs annot newAssoc          -- when queue is not complete, and association list is not empty,
  where xInfo =
          case annot of
            Max -> annotateMax x gr assoc                                 --    1. obtain annot of current node in queue (see getAnnotate; leaf node cases handled)
            Min -> annotateMin x gr assoc
        newAssoc = (x, xInfo) : assoc                                     --    2. add (current node, annot) to assoc list

annotateMax :: GrNode -- node as symbol
            -> LabelledGraph GrNode -- dependency graph
            -> [(GrNode, S.Set GrNode)] -- assoc list of each node and its annotation (all reachable leaves)
            -> S.Set GrNode -- annot corresponding to input node
annotateMax node lg nodeAnnots =
-- if leaf node, then return self, else return reachable leaves
  case sucLG lg node of
    []    -> S.singleton node
    succs -> getUnions succs nodeAnnots

-- predicates: intersection of children's reachable leaves
-- rules: union of children's reachable leaves
annotateMin :: GrNode
            -> LabelledGraph GrNode
            -> [(GrNode, S.Set GrNode)]
            -> S.Set GrNode
annotateMin predN@(PredOr _) lg nodeAnnots =
  case sucLG lg predN of
    []    -> S.singleton predN
    succs -> getIntersections succs nodeAnnots
annotateMin ruleN@(RuleAnd _) lg nodeAnnots =
  getUnions (sucLG lg ruleN) nodeAnnots

sucLG :: Eq a => LabelledGraph a -- dependency graph
      -> a -- node as symbol
      -> [a] -- node successors
sucLG (LG gr indSym symInd) nSym =
  let nInd = bidirLookup symInd nSym
      sInds = suc gr nInd
  in map (bidirLookup indSym) sInds

getUnions :: Ord a => [a] -- successor nodes as symbols
          -> [(a, S.Set a)] -- assoc list of each node and its annotation
          -> S.Set a -- unioned set of reachable leaf preds from all successors
getUnions succs nodeAnnots = S.unions $ M.fromMaybe mempty . flip lookup nodeAnnots <$> succs

getIntersections :: Ord a => [a] -- successor nodes as symbols
                 -> [(a, S.Set a)] -- assoc list of each node and its annotation
                 -> S.Set a -- intersection of reachable leaf preds from all successors
getIntersections succs nodeAnnots = foldr1 S.intersection leaves
  where leaves = M.fromMaybe mempty . flip lookup nodeAnnots <$> succs

-- getAnnotate' :: (Eq a, Ord a) => a -> LabelledGraph a -> [(a, S.Set a)] -> S.Set a
-- getAnnotate' x (LG gr indsym symind) nodeDeps =                       -- if leaf node, then return self, else return children information
--   let xInd = bidirLookup symind x
--       sucSyms = bidirLookup indsym <$> suc gr xInd
--   in case sucSyms of
--     [] -> S.singleton x
--     succs -> getMax succs nodeDeps
