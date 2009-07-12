{-# LANGUAGE ScopedTypeVariables, MultiParamTypeClasses, TypeSynonymInstances, FlexibleInstances #-}

module Language.Haskell.Convert(Convert, convert) where

import Language.Haskell as HS
import Language.Haskell.TH.Syntax as TH
import Control.Exception
import Data.Typeable
import System.IO.Unsafe
import Data.Maybe


class (Typeable a, Typeable b, Show a, Show b) => Convert a b where
    conv :: a -> b


convert :: forall a b . Convert a b => a -> b
convert a = unsafePerformIO $
        (return $! (conv a :: b)) `Control.Exception.catch` (\(e :: SomeException) -> error $ msg e)
    where
        msg e = "Could not convert " ++ show (typeOf a) ++ " to " ++
                show (typeOf (undefined :: b)) ++ "\n" ++ show a ++
                "\n" ++ show e



appT = foldl AppT

c mr = convert mr

instance Convert a b => Convert [a] [b] where
    conv = map c



instance Convert TH.Dec HS.Decl where
    conv x = case x of
        DataD cxt n vs con ds -> f DataType cxt n vs con ds
        NewtypeD cxt n vs con ds -> f NewType cxt n vs [con] ds
        where
            f t cxt n vs con ds = DataDecl sl t (c cxt) (c n) (c vs) (c con) []

instance Convert TH.Name HS.TyVarBind where
    conv = UnkindedVar . c

instance Convert TH.Name HS.Name where
    conv = name . show

instance Convert TH.Con HS.QualConDecl where
    conv (ForallC vs cxt x) = QualConDecl sl (c vs) (c cxt) (c x)
    conv x = QualConDecl sl [] [] (c x)

instance Convert TH.Con HS.ConDecl where
    conv (NormalC n xs) = ConDecl (c n) (c xs)
    conv (RecC n xs) = RecDecl (c n) [([c x], c (y,z)) | (x,y,z) <- xs]
    conv (InfixC x n y) = InfixConDecl (c x) (c n) (c y)

instance Convert TH.StrictType HS.BangType where
    conv (IsStrict, x) = BangedTy $ c x
    conv (NotStrict, x) = UnBangedTy $ c x

instance Convert TH.Type HS.Type where
    conv (ForallT xs cxt t) = TyForall (Just $ c xs) (c cxt) (c t)
    conv (VarT x) = TyVar $ c x
    conv (ConT x) = TyCon $ UnQual $ c x
    conv (AppT (AppT ArrowT x) y) = TyFun (c x) (c y)
    conv (AppT ListT x) = TyList $ c x
    conv (TupleT _) = TyTuple Boxed []
    conv (AppT x y) = case c x of
        TyTuple b xs -> TyTuple b $ xs ++ [c y]
        x -> TyApp x $ c y

instance Convert TH.Type HS.Asst where
    conv (ConT x) = ClassA (UnQual $ c x) []
    conv (AppT x y) = case c x of
        ClassA a b -> ClassA a (b ++ [c y])



instance Convert HS.Decl TH.Dec where
    conv (InstDecl _ cxt nam typ ds) = InstanceD (c cxt) (c $ tyApp (TyCon nam) typ) [c d | InsDecl d <- ds]
    conv (FunBind ms@(HS.Match _ nam _ _ _ _:_)) = FunD (c nam) (c ms)
    conv (PatBind _ p _ bod ds) = ValD (c p) (c bod) (c ds)

instance Convert HS.Asst TH.Type where
    conv (InfixA x y z) = c $ ClassA y [x,z]
    conv (ClassA x y) = appT (ConT $ c x) (c y)

instance Convert HS.Type TH.Type where
    conv (TyParen x) = c x
    conv (TyForall x y z) = ForallT (c $ fromMaybe [] x) (c y) (c z)
    conv (TyVar x) = VarT $ c x
    conv (TyCon x) = ConT $ c x
    conv (TyFun x y) = AppT (AppT ArrowT (c x)) (c y)
    conv (TyList x) = AppT ListT (c x)
    conv (TyTuple _ x) = appT (TupleT (length x)) (c x)
    conv (TyApp x y) = AppT (c x) (c y)

instance Convert HS.Name TH.Name where
    conv = mkName . filter (`notElem` "()") . prettyPrint

instance Convert HS.Match TH.Clause where
    conv (HS.Match _ _ ps _ bod ds) = Clause (c ps) (c bod) (c ds)

instance Convert HS.Rhs TH.Body where
    conv (UnGuardedRhs x) = NormalB (c x)
    conv (GuardedRhss x) = GuardedB (c x)

instance Convert HS.Exp TH.Exp where
    conv (Var x) = VarE (c x)
    conv (Con x) = ConE (c x)
    conv (Lit x) = LitE (c x)
    conv (App x y) = AppE (c x) (c y)
    conv (Paren x) = c x
    conv (InfixApp x y z) = InfixE (Just $ c x) (c y) (Just $ c z)
    conv (LeftSection x y) = InfixE (Just $ c x) (c y) Nothing
    conv (RightSection y z) = InfixE Nothing (c y) (Just $ c z)
    conv (Lambda _ x y) = LamE (c x) (c y)
    conv (Tuple x) = TupE (c x)
    conv (If x y z) = CondE (c x) (c y) (c z)
    conv (Let x y) = LetE (c x) (c y)
    conv (Case x y) = CaseE (c x) (c y)
    conv (Do x) = DoE (c x)
    conv (ListComp x y) = CompE (NoBindS (c x) : c y)
    conv (EnumFrom x) = ArithSeqE $ FromR (c x)
    conv (EnumFromTo x y) = ArithSeqE $ FromToR (c x) (c y)
    conv (EnumFromThen x y) = ArithSeqE $ FromThenR (c x) (c y)
    conv (EnumFromThenTo x y z) = ArithSeqE $ FromThenToR (c x) (c y) (c z)
    conv (List x) = ListE (c x)
    conv (ExpTypeSig _ x y) = SigE (c x) (c y)
    conv (RecConstr x y) = RecConE (c x) (c y)
    conv (RecUpdate x y) = RecUpdE (c x) (c y) 

instance Convert HS.GuardedRhs (TH.Guard, TH.Exp) where
    conv = undefined

instance Convert HS.Binds [TH.Dec] where
    conv (BDecls x) = c x

instance Convert HS.Pat TH.Pat where
    conv (PParen x) = c x
    conv (PLit x) = LitP (c x)
    conv (PTuple x) = TupP (c x)
    conv (PApp x y) = ConP (c x) (c y)
    conv (PVar x) = VarP (c x)
    conv (PInfixApp x y z) = InfixP (c x) (c y) (c z)
    conv (PIrrPat x) = TildeP (c x)
    conv (PAsPat x y) = AsP (c x) (c y)
    conv (PWildCard) = WildP
    conv (PRec x y) = RecP (c x) (c y)
    conv (PList x) = ListP (c x)
    conv (PatTypeSig _ x y) = SigP (c x) (c y)

instance Convert HS.Literal TH.Lit where
    conv (Char x) = CharL x
    conv (String x) = StringL x
    conv (Int x) = IntegerL x
    conv (Frac x) = RationalL x
    conv (PrimInt x) = IntPrimL x
    conv (PrimWord x) = WordPrimL x
    conv (PrimFloat x) = FloatPrimL x
    conv (PrimDouble x) = DoublePrimL x

instance Convert HS.QName TH.Name where
    conv (UnQual x) = c x

instance Convert HS.PatField TH.FieldPat where
    conv = undefined

instance Convert HS.QOp TH.Exp where
    conv (QVarOp x) = c $ Var x
    conv (QConOp x) = c $ Con x

instance Convert HS.Alt TH.Match where
    conv (Alt _ x y z) = TH.Match (c x) (c y) (c z)

instance Convert HS.Stmt TH.Stmt where
    conv (Generator _ x y) = BindS (c x) (c y)
    conv (LetStmt x) = LetS (c x)
    conv (Qualifier x) = NoBindS (c x)

instance Convert HS.QualStmt TH.Stmt where
    conv = undefined

instance Convert HS.FieldUpdate TH.FieldExp where
    conv = undefined

instance Convert HS.TyVarBind TH.Name where
    conv = undefined

instance Convert HS.GuardedAlts TH.Body where
    conv (UnGuardedAlt x) = NormalB (c x)
    conv (GuardedAlts x) = GuardedB (c x)

instance Convert HS.GuardedAlt (TH.Guard, TH.Exp) where
    conv (GuardedAlt _ x y) = (PatG (c x), c y)