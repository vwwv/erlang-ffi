> {-# LANGUAGE OverlappingInstances #-}
> {-# OPTIONS -XFlexibleInstances -XTypeSynonymInstances #-}

> module Foreign.Erlang.Types (
>   -- * Native Erlang data types.
>   -- ** Haskell representation.
>     ErlType(..)
>   -- ** Conversion between native Haskell types and ErlType.
>   , Erlang
>   , fromErlang
>   , toErlang
>   -- ** Easy type-safe access to tuple members.
>   , nth
>
>   -- ** Internal packing functions.
>   , getA, getC, getErl, getN, geta, getn
>   , putA, putC, putErl, putN, puta, putn
>   , tag
>   ) where

> import Control.Exception  (assert)
> import Control.Monad      (forM, liftM)
> import Data.Monoid ((<>),mconcat)
> import Data.Binary
> import Data.Binary.Get
> import Data.Binary.Put
> import Data.Char          (chr, ord, isLetter)
> import qualified Data.ByteString.Lazy       as B
> import qualified Data.ByteString.Lazy.Char8 as C
> import Data.ByteString.Lazy.Builder

> nth                  :: Erlang a => Int -> ErlType -> a
> nth i (ErlTuple lst) = fromErlang $ lst !! i

> data ErlType = ErlNull
>              | ErlInt Int
>              | ErlBigInt Integer
>              | ErlString String
>              | ErlAtom String
>              | ErlBinary [Word8]
>              | ErlList [ErlType]
>              | ErlTuple [ErlType]
>              | ErlPid ErlType Int Int Int     -- node id serial creation
>              | ErlPort ErlType Int Int        -- node id creation
>              | ErlRef ErlType Int Int         -- node id creation
>              | ErlNewRef ErlType Int [Word8]  -- node creation id
>              deriving (Eq, Show)

> class Erlang a where
>     toErlang   :: a -> ErlType
>     fromErlang :: ErlType -> a

> instance Erlang ErlType where
>     toErlang   = id
>     fromErlang = id

> instance Erlang Int where
>     toErlang   x             = ErlInt x
>     fromErlang (ErlInt x)    = x
>     fromErlang (ErlBigInt x) = fromIntegral x

> instance Erlang Integer where
>     toErlang   x             = ErlBigInt x
>     fromErlang (ErlInt x)    = fromIntegral x
>     fromErlang (ErlBigInt x) = x

> instance Erlang String where
>     toErlang   x             = ErlString x
>     fromErlang ErlNull       = ""
>     fromErlang (ErlString x) = x
>     fromErlang (ErlAtom x)   = x
>     fromErlang (ErlList xs)  = map (chr . fromErlang) xs
>     fromErlang x             = error $ "can't convert to string: " ++ show x

> instance Erlang Bool where
>     toErlang   True              = ErlAtom "true"
>     toErlang   False             = ErlAtom "false"
>     fromErlang (ErlAtom "true")  = True
>     fromErlang (ErlAtom "false") = False

> instance Erlang [ErlType] where
>     toErlang   []           = ErlNull
>     toErlang   xs           = ErlList xs
>     fromErlang ErlNull      = []
>     fromErlang (ErlList xs) = xs

> instance Erlang a => Erlang [a] where
>     toErlang   []           = ErlNull
>     toErlang   xs           = ErlList . map toErlang $ xs
>     fromErlang ErlNull      = []
>     fromErlang (ErlList xs) = map fromErlang xs

> instance (Erlang a, Erlang b) => Erlang (a, b) where
>     toErlang   (x, y)            = ErlTuple [toErlang x, toErlang y]
>     fromErlang (ErlTuple [x, y]) = (fromErlang x, fromErlang y)

> instance (Erlang a, Erlang b, Erlang c) => Erlang (a, b, c) where
>     toErlang   (x, y, z)            = ErlTuple [toErlang x, toErlang y, toErlang z]
>     fromErlang (ErlTuple [x, y, z]) = (fromErlang x, fromErlang y, fromErlang z)

> instance (Erlang a, Erlang b, Erlang c, Erlang d) => Erlang (a, b, c, d) where
>     toErlang   (x, y, z, w)            = ErlTuple [toErlang x, toErlang y, toErlang z, toErlang w]
>     fromErlang (ErlTuple [x, y, z, w]) = (fromErlang x, fromErlang y, fromErlang z, fromErlang w)

> instance (Erlang a, Erlang b, Erlang c, Erlang d, Erlang e) => Erlang (a, b, c, d, e) where
>     toErlang   (x, y, z, w, a)            = ErlTuple [toErlang x, toErlang y, toErlang z, toErlang w, toErlang a]
>     fromErlang (ErlTuple [x, y, z, w, a]) = (fromErlang x, fromErlang y, fromErlang z, fromErlang w, fromErlang a)

> instance Binary ErlType where
>     put = undefined
>     get = getErl

      
> putErl :: ErlType -> Builder
> putErl (ErlInt val)
>     | 0 <= val && val < 256 = tag 'a' <> putC val
>     | otherwise             = tag 'b' <> putN val
> putErl (ErlAtom val)        = tag 'd' <> putn (length val) <> putA val
> putErl (ErlTuple val)
>     | len < 256             = tag 'h' <> putC len <> val'
>     | otherwise             = tag 'i' <> putN len <> val'
>     where val' = mconcat . map putErl $ val
>           len  = length val
> putErl ErlNull              = tag 'j'
> putErl (ErlString val)      = tag 'k' <> putn (length val) <> putA val
> putErl (ErlList val)        = tag 'l' <> putN (length val) <> val' <> putErl ErlNull
>     where val' = mconcat . map putErl $ val  
> putErl (ErlBinary val)      = tag 'm' <> putN (length val) <> (lazyByteString . B.pack) val
> putErl (ErlRef node id creation) =
>     tag 'e' <>
>     putErl node <>
>     putN id <>
>     putC creation
> putErl (ErlPort node id creation) = tag 'f' <> putErl node <> putN id <> putC creation
> putErl (ErlPid node id serial creation) = tag 'g' <> putErl node <> putN id <> putN serial <> putC creation
> putErl (ErlNewRef node creation id) =
>     tag 'r' <>
>     putn (length id `div` 4) <>
>     putErl node <>
>     putC creation <>
>     (lazyByteString . B.pack) id
        
> getErl = do
>     tag <- liftM chr getC
>     case tag of
>       'a' -> liftM ErlInt getC
>       'b' -> liftM ErlInt getN
>       'd' -> getn >>= liftM ErlAtom . getA
>       'e' -> do
>         node <- getErl
>         id <- getN
>         creation <- getC
>         return $ ErlRef node id creation
>       'f' -> do
>         node <- getErl
>         id <- getN
>         creation <- getC
>         return $ ErlPort node id creation
>       'g' -> do
>         node <- getErl
>         id <- getN
>         serial <- getN
>         creation <- getC
>         return $ ErlPid node id serial creation
>       'h' -> getC >>= \len -> liftM ErlTuple $ forM [1..len] (const getErl)
>       'i' -> getN >>= \len -> liftM ErlTuple $ forM [1..len] (const getErl)
>       'j' -> return ErlNull
>       'k' -> do
>          len <- getn
>          list <- getA len
>          case all isLetter list of
>            True -> return $ ErlString list
>            False -> return . ErlList $ map (ErlInt . ord) list
>       'l' -> do
>         len <- getN
>         list <- liftM ErlList $ forM [1..len] (const getErl)
>         null <- getErl
>         assert (null == ErlNull) $ return list
>       'm' -> getN >>= liftM ErlBinary . geta
>       'r' -> do
>         len <- getn
>         node <- getErl
>         creation <- getC
>         id <- forM [1..4*len] (const getWord8)
>         return $ ErlNewRef node creation id
>       x -> error [x]

> tag :: Char -> Builder             
> tag = putC . ord

> putC :: Integral a => a -> Builder
> putC = word8 . fromIntegral

> putn :: Integral a => a -> Builder
> putn = word16BE . fromIntegral

> putN :: Integral a => a -> Builder
> putN = word32BE . fromIntegral

> puta :: [Word8] -> Builder
> puta = lazyByteString . B.pack

> putA :: String -> Builder       
> putA = lazyByteString . C.pack

> getC = liftM fromIntegral getWord8
>
> getn :: Num r => Get r
> getn = liftM fromIntegral getWord16be
>
> getN :: Num r => Get r
> getN = liftM fromIntegral getWord32be
> geta = liftM B.unpack . getLazyByteString
> getA = liftM C.unpack . getLazyByteString
