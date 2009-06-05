{-| 

A ledger-compatible @balance@ command. 

ledger's balance command is easy to use but not easy to describe
precisely.  In the examples below we'll use sample.ledger, which has the
following account tree:

@
 assets
   bank
     checking
     saving
   cash
 expenses
   food
   supplies
 income
   gifts
   salary
 liabilities
   debts
@

The balance command shows accounts with their aggregate balances.
Subaccounts are displayed indented below their parent. Each balance is the
sum of any transactions in that account plus any balances from
subaccounts:

@
 $ hledger -f sample.ledger balance
                 $-1  assets
                  $1    bank:saving
                 $-2    cash
                  $2  expenses
                  $1    food
                  $1    supplies
                 $-2  income
                 $-1    gifts
                 $-1    salary
                  $1  liabilities:debts
@

Usually, the non-interesting accounts are elided or omitted. Above,
@checking@ is omitted because it has no subaccounts and a zero balance.
@bank@ is elided because it has only a single displayed subaccount
(@saving@) and it would be showing the same balance as that ($1). Ditto
for @liabilities@. We will return to this in a moment.

The --depth argument can be used to limit the depth of the balance report.
So, to see just the top level accounts:

@
$ hledger -f sample.ledger balance --depth 1
                 $-1  assets
                  $2  expenses
                 $-2  income
                  $1  liabilities
@

This time liabilities has no displayed subaccounts (due to --depth) and
is not elided.

With one or more account pattern arguments, the balance command shows
accounts whose name matches one of the patterns, plus their parents
(elided) and subaccounts. So with the pattern o we get:

@
 $ hledger -f sample.ledger balance o
                  $1  expenses:food
                 $-2  income
                 $-1    gifts
                 $-1    salary
--------------------
                 $-1
@

The o pattern matched @food@ and @income@, so they are shown. Unmatched
parents of matched accounts are also shown (elided) for context (@expenses@).

Also, the balance report shows the total of all displayed accounts, when
that is non-zero. Here, it is displayed because the accounts shown add up
to $-1.

Here is a more precise definition of \"interesting\" accounts in ledger's
balance report:

- an account which has just one interesting subaccount branch, and which
  is not at the report's maximum depth, is interesting if the balance is
  different from the subaccount's, and otherwise boring.

- any other account is interesting if it has a non-zero balance, or the -E
  flag is used.

-}

module Commands.Balance
where
import Prelude hiding (putStr)
import Ledger.Utils
import Ledger.Types
import Ledger.Amount
import Ledger.AccountName
import Ledger.Transaction
import Ledger.Ledger
import Options
import System.IO.UTF8


-- | Print a balance report.
balance :: [Opt] -> [String] -> Ledger -> IO ()
balance opts args l = putStr $ showBalanceReport opts args l

-- | Generate a balance report with the specified options for this ledger.
showBalanceReport :: [Opt] -> [String] -> Ledger -> String
showBalanceReport opts _ l = acctsstr ++ totalstr
    where 
      acctsstr = unlines $ map showacct interestingaccts
          where
            showacct = showInterestingAccount l interestingaccts
            interestingaccts = filter (isInteresting opts l) acctnames
            acctnames = sort $ tail $ flatten $ treemap aname accttree
            accttree = ledgerAccountTree (depthFromOpts opts) l
      totalstr | NoTotal `elem` opts = ""
               | not (Empty `elem` opts) && isZeroMixedAmount total = ""
               | otherwise = printf "--------------------\n%s\n" $ padleft 20 $ showMixedAmount total
          where
            total = sum $ map abalance $ ledgerTopAccounts l

-- | Display one line of the balance report with appropriate indenting and eliding.
showInterestingAccount :: Ledger -> [AccountName] -> AccountName -> String
showInterestingAccount l interestingaccts a = concatTopPadded [amt, "  ", depthspacer ++ partialname]
    where
      amt = padleft 20 $ showMixedAmount $ abalance $ ledgerAccount l a
      -- the depth spacer (indent) is two spaces for each interesting parent
      parents = parentAccountNames a
      interestingparents = filter (`elem` interestingaccts) parents
      depthspacer = replicate (2 * length interestingparents) ' '
      -- the partial name is the account's leaf name, prefixed by the
      -- names of any boring parents immediately above
      partialname = accountNameFromComponents $ (reverse $ map accountLeafName ps) ++ [accountLeafName a]
          where ps = takeWhile boring parents where boring = not . (`elem` interestingparents)

-- | Is the named account considered interesting for this ledger's balance report ?
isInteresting :: [Opt] -> Ledger -> AccountName -> Bool
isInteresting opts l a
    | numinterestingsubs==1 && not atmaxdepth = notlikesub
    | otherwise = notzero || emptyflag
    where
      atmaxdepth = accountNameLevel a == depthFromOpts opts
      emptyflag = Empty `elem` opts
      acct = ledgerAccount l a
      notzero = not $ isZeroMixedAmount inclbalance where inclbalance = abalance acct
      notlikesub = not $ isZeroMixedAmount exclbalance where exclbalance = sumTransactions $ atransactions acct
      numinterestingsubs = length $ filter isInterestingTree subtrees
          where
            isInterestingTree t = treeany (isInteresting opts l . aname) t
            subtrees = map (fromJust . ledgerAccountTreeAt l) $ ledgerSubAccounts l $ ledgerAccount l a
