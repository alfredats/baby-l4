module Parser.SmartConstructors where

import Annotation
import Syntax
import Lexer

-- Smart constructors for automatically adding location information to the ast

binOpE :: BinOp -> Expr SRng -> Expr SRng -> Expr SRng
binOpE op a b = BinOpE (tokenRange a b) op a b

unaOpE :: HasLoc f => UnaOp -> f -> Expr SRng -> Expr SRng
unaOpE op opTok e = UnaOpE (tokenRange opTok e) op e

ifThenElseE :: Token -> Expr SRng -> Expr SRng -> Expr SRng -> Expr SRng
ifThenElseE ifTok i t e = IfThenElseE (tokenRange ifTok e) i t e

varE :: Token -> Expr SRng
varE v = VarE (tokenPos v) (GlobalVar $ tokenSym v)

appE :: Expr SRng -> Expr SRng -> Expr SRng
appE f x = AppE (tokenRange f x) f x

notDeriv :: Bool -> Token -> Expr SRng -> Expr SRng
notDeriv b tok e = NotDeriv (tokenRange tok e) b e

quantifE :: Quantif -> Token -> Token -> Located Tp -> Expr SRng -> Expr SRng
quantifE quant quantTok v tp e = QuantifE (tokenRange quantTok e) quant (tokenSym v) (unLoc tp) e

funE :: Token -> Pattern -> Located Tp -> Expr SRng -> Expr SRng
funE tok pat atp e = FunE (tokenRange tok e) pat (unLoc atp) e

boolVE :: Bool -> Token -> Expr SRng
boolVE v tok = ValE (tokenPos tok) (BoolV v)

numVE :: Token -> Expr SRng
numVE tok = ValE (tokenPos tok) $ IntV    $ tokenNum tok

strVE :: Token -> Expr SRng
strVE tok = ValE (tokenPos tok) $ StringV $ tokenString tok


tokenSym' :: TokenKind -> String
tokenSym'    (TokenSym sym) = sym
tokenString' :: TokenKind -> String
tokenString' (TokenString str) = str
tokenStringLit' :: TokenKind -> String
tokenStringLit' (TokenStringLit str) = str
tokenNum' :: TokenKind -> Integer
tokenNum' (TokenNum num) = num

-- tokenSym    = tokenSym' . unLoc
tokenSym    (L _ (TokenSym sym)) = sym
tokenString (L _ (TokenString str)) = str
tokenStringLit (L _ (TokenStringLit str)) = str
tokenNum (L _ (TokenNum num)) = num