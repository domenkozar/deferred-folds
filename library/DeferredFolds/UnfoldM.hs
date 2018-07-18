module DeferredFolds.UnfoldM
where

import DeferredFolds.Prelude hiding (mapM_)
import qualified DeferredFolds.Prelude as A


{-|
A monadic variation of "DeferredFolds.Unfold"
-}
newtype UnfoldM m input =
  UnfoldM (forall output. (output -> input -> m output) -> output -> m output)

deriving instance Functor m => Functor (UnfoldM m)

instance Monad m => Applicative (UnfoldM m) where
  pure x =
    UnfoldM (\ step init -> step init x)
  (<*>) = ap

instance Monad m => Alternative (UnfoldM m) where
  empty =
    UnfoldM (const return)
  {-# INLINE (<|>) #-}
  (<|>) (UnfoldM left) (UnfoldM right) =
    UnfoldM (\ step init -> left step init >>= right step)

instance Monad m => Monad (UnfoldM m) where
  return = pure
  (>>=) (UnfoldM left) rightK =
    UnfoldM $ \ step init ->
    let
      newStep output x =
        case rightK x of
          UnfoldM right ->
            right step output
      in left newStep init

instance Monad m => MonadPlus (UnfoldM m) where
  mzero = empty
  mplus = (<|>)

instance Monad m => Semigroup (UnfoldM m a) where
  (<>) = (<|>)

instance Monad m => Monoid (UnfoldM m a) where
  mempty = empty
  mappend = (<>)

instance Foldable (UnfoldM Identity) where
  {-# INLINE foldMap #-}
  foldMap inputMonoid = foldl' step mempty where
    step monoid input = mappend monoid (inputMonoid input)
  foldl = foldl'
  {-# INLINE foldl' #-}
  foldl' step init (UnfoldM run) =
    runIdentity (run identityStep init)
    where
      identityStep state input = return (step state input)

{-| Perform a monadic strict left fold -}
{-# INLINE foldlM' #-}
foldlM' :: Monad m => (output -> input -> m output) -> output -> UnfoldM m input -> m output
foldlM' step init (UnfoldM run) =
  run step init

{-# INLINE mapM_ #-}
mapM_ :: Monad m => (input -> m ()) -> UnfoldM m input -> m ()
mapM_ step = foldlM' (const step) ()

{-# INLINE forM_ #-}
forM_ :: Monad m => UnfoldM m input -> (input -> m ()) -> m ()
forM_ = flip mapM_

{-| Apply a Gonzalez fold -}
{-# INLINE fold #-}
fold :: Fold input output -> UnfoldM Identity input -> output
fold (Fold step init extract) = extract . foldl' step init

{-| Apply a monadic Gonzalez fold -}
{-# INLINE foldM #-}
foldM :: Monad m => FoldM m input output -> UnfoldM m input -> m output
foldM (FoldM step init extract) view =
  do
    initialState <- init
    finalState <- foldlM' step initialState view
    extract finalState

{-| Construct from any foldable -}
{-# INLINE foldable #-}
foldable :: (Monad m, Foldable foldable) => foldable a -> UnfoldM m a
foldable foldable = UnfoldM (\ step init -> A.foldlM step init foldable)

{-# INLINE filter #-}
filter :: Monad m => (a -> m Bool) -> UnfoldM m a -> UnfoldM m a
filter test (UnfoldM run) = UnfoldM (\ step -> run (\ state element -> test element >>= bool (return state) (step state element)))

{-| Ints in the specified inclusive range -}
intsInRange :: Monad m => Int -> Int -> UnfoldM m Int
intsInRange from to =
  UnfoldM $ \ step init ->
  let
    loop !state int =
      if int <= to
        then do
          newState <- step state int
          loop newState (succ int)
        else return state
    in loop init from