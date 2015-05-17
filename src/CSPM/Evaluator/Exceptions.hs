module CSPM.Evaluator.Exceptions
where

import Prelude

import CSPM.Syntax.Names
import CSPM.Syntax.AST
import CSPM.PrettyPrinter
import CSPM.Evaluator.ValuePrettyPrinter ()
import CSPM.Evaluator.Values
import CSPM.Evaluator.ValueSet hiding (empty)
import Util.Annotated
import Util.Exception
import Util.PrettyPrint

printCallStack :: Maybe InstantiatedFrame -> Doc
printCallStack Nothing = text "Lexical call stack: none available"
--printCallStack (Just p) =
--    let ppFrame _ Nothing = empty
--        ppFrame i (Just (SFunctionBind h n vss p)) =
--            int i <> colon <+> prettyPrint (SFunctionBind h n vss Nothing)
--            $$ ppFrame (i+1) p
--        ppFrame i (Just (SVariableBind h vs p)) =
--            int i <> colon <+> prettyPrint (SVariableBind h vs Nothing)
--            $$ ppFrame (i+1) p
--    in text "Lexical call stack:" $$ tabIndent (ppFrame 1 (Just p))


patternMatchFailureMessage :: SrcSpan -> TCPat -> Value -> ErrorMessage
patternMatchFailureMessage l pat v =
    mkErrorMessage l $ 
        hang (hang (text "Pattern match failure: Value") tabWidth
                (prettyPrint v))
            tabWidth (text "does not match the pattern" <+> prettyPrint pat)

patternMatchesFailureMessage :: SrcSpan -> [TCPat] -> [Value] -> ErrorMessage
patternMatchesFailureMessage l pat v =
    mkErrorMessage l $ 
        hang (hang (text "Pattern match failure: ") tabWidth
                (list (map prettyPrint v)))
            tabWidth (text "do not match the patterns" <+>
                list (map prettyPrint pat))

headEmptyListMessage :: SrcSpan -> Maybe InstantiatedFrame -> ErrorMessage
headEmptyListMessage loc scope = mkErrorMessage loc $ 
    text "Attempt to take head of empty list."
    $$ printCallStack scope

prioritiseEmptyListMessage :: SrcSpan -> Maybe InstantiatedFrame -> ErrorMessage
prioritiseEmptyListMessage loc scope = mkErrorMessage loc $ 
    text "Prioritise must be called with a non-empty list."
    $$ printCallStack scope

tailEmptyListMessage :: SrcSpan -> Maybe InstantiatedFrame -> ErrorMessage
tailEmptyListMessage loc scope = mkErrorMessage loc $ 
    text "Attempt to take tail of empty list."
    $$ printCallStack scope

divideByZeroMessage :: SrcSpan -> Maybe InstantiatedFrame -> ErrorMessage
divideByZeroMessage loc scope = mkErrorMessage loc $
    text "Attempt to divide by zero"
    $$ printCallStack scope

keyNotInDomainOfMapMessage :: SrcSpan -> Maybe InstantiatedFrame -> ErrorMessage
keyNotInDomainOfMapMessage loc scope = mkErrorMessage loc $
    text "Lookup called on a key that is not in the domain of the map."
    $$ printCallStack scope

funBindPatternMatchFailureMessage :: SrcSpan -> Name -> [[Value]] -> ErrorMessage
funBindPatternMatchFailureMessage l n vss = mkErrorMessage l $
    hang (text "Pattern match failure whilst attempting to evaluate:") tabWidth
        (prettyPrint n <> 
            hcat (map (\ vs -> parens (list (map prettyPrint vs))) vss))

replicatedLinkParallelOverEmptySeqMessage :: Exp Name -> SrcSpan ->
    Maybe InstantiatedFrame -> ErrorMessage
replicatedLinkParallelOverEmptySeqMessage p l scope = mkErrorMessage l $
    hang (
        hang (text "The sequence expression in"<>colon) tabWidth 
            (prettyPrint p)
    ) tabWidth
    (text "evaluated to the empty sequence. However, replicated linked parallel is not defined for the empty sequence.")
    $$ printCallStack scope

replicatedInternalChoiceOverEmptySetMessage :: TCExp -> 
    Maybe InstantiatedFrame -> ErrorMessage
replicatedInternalChoiceOverEmptySetMessage p scope = mkErrorMessage (loc p) $
    hang (
        hang (text "The set expression in"<>colon) tabWidth 
            (prettyPrint p)
    ) tabWidth
    (text "evaluated to the empty set. However, replicated internal choice is not defined for the empty set.")
    $$ printCallStack scope

replicatedInternalChoiceOverEmptySetMessage' :: TCPat ->
    Maybe InstantiatedFrame -> ErrorMessage
replicatedInternalChoiceOverEmptySetMessage' p scope = mkErrorMessage (loc p) $
    hang (
        hang (text "The pattern"<>colon) tabWidth (prettyPrint p)
    ) tabWidth
    (text "matched no elements of the channel set. However, replicated internal choice is not defined for the empty set.")
    $$ printCallStack scope

typeCheckerFailureMessage :: String -> ErrorMessage
typeCheckerFailureMessage s = mkErrorMessage Unknown $
    hang (text "The program caused a runtime error that should have been caught by the typechecker:")
        tabWidth (text s)

cannotConvertIntegersToListMessage :: ErrorMessage
cannotConvertIntegersToListMessage = mkErrorMessage Unknown $
    text "Cannot convert the set of all integers into a list."

cannotConvertProcessesToListMessage :: ErrorMessage
cannotConvertProcessesToListMessage = mkErrorMessage Unknown $
    text "Cannot convert the set of all processes (i.e. Proc) into a list."

cannotCheckSetMembershipError :: Value -> ValueSet -> ErrorMessage
cannotCheckSetMembershipError v vs = mkErrorMessage Unknown $
    text "Cannot check for set membership as the supplied set is infinite."

cardOfInfiniteSetMessage :: ValueSet -> ErrorMessage
cardOfInfiniteSetMessage vs = mkErrorMessage Unknown $
    text "Attempt to take the cardinatlity of an infinite set."

cannotDifferenceSetsMessage :: ValueSet -> ValueSet -> ErrorMessage
cannotDifferenceSetsMessage vs1 vs2 = mkErrorMessage Unknown $
    text "Cannot difference the supplied sets."

dotIsNotValidMessage :: Value -> Int -> Value -> ValueSet -> SrcSpan ->
    Maybe InstantiatedFrame -> ErrorMessage
dotIsNotValidMessage (value@(VDot (h:_))) field fieldValue fieldOptions loc scope =
    mkErrorMessage loc $
        hang (text "The value:") tabWidth (prettyPrint value)
        $$ text "is invalid as it is not within the set of values defined for" <+>
            case h of
                VChannel n -> text "the channel" <+> prettyPrint n <> char '.'
                VDataType n -> text "the data constructor" <+> prettyPrint n <> char '.'
        $$ hang (text "In particular the" <+> speakNth (field+1) <+> text "field:") tabWidth (prettyPrint fieldValue)
        $$ hang (text "is not a member of the set") tabWidth (prettyPrint fieldOptions)
        $$ printCallStack scope

setNotRectangularErrorMessage :: SrcSpan -> ValueSet -> Maybe ValueSet -> ErrorMessage
setNotRectangularErrorMessage loc s1 ms2 = mkErrorMessage loc $
    hang (text "The set:") tabWidth (prettyPrint s1)
    $$ text "cannot be decomposed into a cartesian product (i.e. it is not rectangular)."
    $$ case ms2 of
        Just s2 -> 
            hang (text "The cartesian product is equal to:") tabWidth 
                -- Force evaluation to a proper set, not a cart product.
                (prettyPrint (fromList (toList s2)))
            $$ hang (text "and thus the following values are missing:") tabWidth
                (prettyPrint (difference s2 s1))
        Nothing -> empty

prioritisePartialOrderCyclicOrder :: [Event] -> SrcSpan ->
    Maybe InstantiatedFrame -> ErrorMessage
prioritisePartialOrderCyclicOrder scc loc scid = mkErrorMessage loc $
    text "The partial order specified for priortisepo contains the following cycle:"
    $$ tabIndent (list (map prettyPrint scc))

prioritiseNonMaximalElement :: Event -> SrcSpan -> Maybe InstantiatedFrame -> ErrorMessage
prioritiseNonMaximalElement event loc scid = mkErrorMessage loc $
    text "The event:" <+> prettyPrint event
    <+> text "is declared as maximal, but is not maximal in the order."

prioritisePartialOrderEventsMissing :: [Event] -> [Event] -> SrcSpan ->
    Maybe InstantiatedFrame -> ErrorMessage
prioritisePartialOrderEventsMissing allEvents missingEvents loc scid = mkErrorMessage loc $
    text "The events:"
    $$ tabIndent (list (map prettyPrint missingEvents))
    $$ text "appear in the partial order, or in the set of maximal events, but are"
    $$ text "not in the set of all prioritised events:"
    $$ tabIndent (list (map prettyPrint allEvents))
