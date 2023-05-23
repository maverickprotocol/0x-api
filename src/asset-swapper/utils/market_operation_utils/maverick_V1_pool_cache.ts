import { ChainId } from '@0x/contract-addresses';
import { BigNumber } from '@0x/utils';
import { getAddress } from '@ethersproject/address';
import { gql, request } from 'graphql-request';

import { DEFAULT_WARNING_LOGGER } from '../../constants';
import { LogFunction } from '../../types';
import { MAVERICK_V1_SUBGRAPH_URL_BY_CHAIN, ONE_HOUR_IN_SECONDS, ONE_SECOND_MS } from './constants';

const MAVERICK_V1_SUBGRAPH_URL = 'https://api.thegraph.com/subgraphs/name/maverickprotocol/maverick-mainnet';
const MAVERICK_V1_TOP_POOLS_FETCHED = 250;
const ONE_DAY_MS = 24 * 60 * 60 * 1000;
const DEFAULT_CACHE_TIME_MS = (ONE_HOUR_IN_SECONDS / 2) * ONE_SECOND_MS;
const DEFAULT_TIMEOUT_MS = 3000;
export interface CacheValue {
    expiresAt: number;
    pools: string[];
}

interface MaverickV1PoolResponse {
    id: string;
    tokenA: { id: string; decimals: number };
    tokenB: { id: string; decimals: number };
    balanceUSD: BigNumber;
}
export class MaverickV1PoolsCache {
    public static create(chainId: ChainId): MaverickV1PoolsCache {
        return new MaverickV1PoolsCache(MAVERICK_V1_SUBGRAPH_URL_BY_CHAIN[chainId]);
    }

    private constructor(
        private readonly _subgraphUrl: string | null = MAVERICK_V1_SUBGRAPH_URL,
        protected readonly _cache: Map<string, CacheValue> = new Map(),
        private readonly _topPoolsFetched: number = MAVERICK_V1_TOP_POOLS_FETCHED,
        private readonly _warningLogger: LogFunction = DEFAULT_WARNING_LOGGER,
        protected readonly _cacheTimeMs: number = DEFAULT_CACHE_TIME_MS,
    ) {
        void this._loadTopPoolsAsync();
        // Reload the top pools every 12 hours
        setInterval(async () => void this._loadTopPoolsAsync(), ONE_DAY_MS / 2);
    }

    protected _isExpired(value: CacheValue | undefined): boolean {
        if (value === undefined) {
            return true;
        }
        return Date.now() >= value.expiresAt;
    }

    public async getFreshPoolsForPairAsync(
        takerToken: string,
        makerToken: string,
        timeoutMs: number = DEFAULT_TIMEOUT_MS,
    ): Promise<string[]> {
        const timeout = new Promise<string[]>((resolve) => setTimeout(resolve, timeoutMs, []));
        return Promise.race([this._getAndSaveFreshPoolsForPairAsync(takerToken, makerToken), timeout]);
    }

    public isFresh(takerToken: string, makerToken: string): boolean {
        const value = this._getValue(takerToken, makerToken);
        return !this._isExpired(value);
    }

    protected async _getAndSaveFreshPoolsForPairAsync(takerToken: string, makerToken: string): Promise<string[]> {
        const key = this._getKey(takerToken, makerToken);
        const value = this._cache.get(key);
        if (!this._isExpired(value)) {
            // eslint-disable-next-line @typescript-eslint/no-non-null-assertion -- TODO: fix me!
            return value!.pools;
        }

        const pools = await this._fetchPoolsForPairAsync(takerToken, makerToken);

        const expiresAt = Date.now() + this._cacheTimeMs;
        this._cachePoolsForPair(takerToken, makerToken, pools, expiresAt);
        return pools;
    }

    protected async _fetchPoolsForPairAsync(takerToken: string, makerToken: string): Promise<string[]> {
        try {
            let pools: MaverickV1PoolResponse[];
            try {
                pools = await this._fetchTopPoolsAsync();
                return pools
                    .filter((pool) => {
                        const tokenA =
                            new BigNumber(getAddress(takerToken)) < new BigNumber(getAddress(makerToken))
                                ? getAddress(takerToken)
                                : getAddress(makerToken);
                        const tokenB =
                            new BigNumber(getAddress(takerToken)) < new BigNumber(getAddress(makerToken))
                                ? getAddress(makerToken)
                                : getAddress(takerToken);

                        if (tokenA == getAddress(pool.tokenA.id) && tokenB == getAddress(pool.tokenB.id)) {
                            return true;
                        }
                    })
                    .map((pool) => getAddress(pool.id));
            } catch (err) {
                this._warningLogger(err, 'Failed to fetch top pools for Maverick V1');
                return [];
            }
        } catch (err) {
            return [];
        }
    }

    public getPoolAddressesForPair(takerToken: string, makerToken: string): string[] {
        const value = this._getValue(takerToken, makerToken);
        return value === undefined ? [] : value.pools;
    }

    protected _getValue(takerToken: string, makerToken: string): CacheValue | undefined {
        const key = this._getKey(takerToken, makerToken);
        return this._cache.get(key);
    }

    protected async _loadTopPoolsAsync(): Promise<void> {
        const fromToPools: {
            [from: string]: { [to: string]: string[] };
        } = {};
        let pools: MaverickV1PoolResponse[];
        try {
            pools = await this._fetchTopPoolsAsync();
        } catch (err) {
            this._warningLogger(err, 'Failed to fetch top pools for Maverick V1');
            return;
        }

        for (const pool of pools) {
            const tokenA = getAddress(pool.tokenA.id);
            const tokenB = getAddress(pool.tokenB.id);
            fromToPools[tokenA] = fromToPools[tokenA] || {};
            fromToPools[tokenA][tokenB] = fromToPools[tokenA][tokenB] || [];
            try {
                fromToPools[tokenA][tokenB].push(pool.id);
                const expiresAt = Date.now() + this._cacheTimeMs;
                this._cachePoolsForPair(tokenA, tokenB, fromToPools[tokenA][tokenB], expiresAt);
            } catch {}
        }
    }

    protected _getKey(takerToken: string, makerToken: string): string {
        const tokenA =
            new BigNumber(getAddress(takerToken)) < new BigNumber(getAddress(makerToken))
                ? getAddress(takerToken)
                : getAddress(makerToken);
        const tokenB =
            new BigNumber(getAddress(takerToken)) < new BigNumber(getAddress(makerToken))
                ? getAddress(makerToken)
                : getAddress(takerToken);
        return `${tokenA}-${tokenB}`;
    }

    protected _cachePoolsForPair(takerToken: string, makerToken: string, pools: string[], expiresAt: number): void {
        const key = this._getKey(takerToken, makerToken);
        this._cache.set(key, { pools, expiresAt });
    }

    protected async _fetchTopPoolsAsync(): Promise<MaverickV1PoolResponse[]> {
        const query = gql`
            query ($topPoolsFetched: Int) {
                pools(first: $topPoolsFetched, orderBy: balanceUSD, orderDirection: desc) {
                    id
                    tokenA {
                        id
                        decimals
                    }
                    tokenB {
                        id
                        decimals
                    }
                    balanceUSD
                }
            }
        `;
        try {
            if (this._subgraphUrl) {
                const res = await request(this._subgraphUrl, query, { topPoolsFetched: this._topPoolsFetched });
                return res.pools;
            }
            return [];
        } catch (err) {
            return [];
        }
    }
}
